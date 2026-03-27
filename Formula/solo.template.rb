require "etc"

class Solo < Formula
  desc "An opinionated CLI tool to deploy and manage standalone test networks."
  homepage "https://github.com/hiero-ledger/solo"

  url "https://registry.npmjs.org/@hashgraph/solo/-/solo-__SOLO_VERSION__.tgz"
  sha256 "__SOLO_SHA256__"
  version "__SOLO_VERSION__"

  depends_on "node"

  # Returns true only for targets managed by Homebrew's own `solo` or versioned `solo@X`.
  # This prevents us from deleting Homebrew-owned symlinks during conflict cleanup.
  def homebrew_managed_solo_target?(target)
    allow_prefixes = [
      (HOMEBREW_PREFIX/"Cellar/solo").to_s,
      (HOMEBREW_PREFIX/"Cellar/solo@").to_s,
      (HOMEBREW_PREFIX/"opt/solo").to_s,
      (HOMEBREW_PREFIX/"opt/solo@").to_s,
    ]
    allow_prefixes.any? { |prefix| target.start_with?(prefix) }
  end

  # Resolves a path target safely:
  # - regular file: return the path itself
  # - symlink with valid target: return realpath
  # - dangling symlink: return readlink target instead of raising
  # This keeps diagnostics actionable even when stale links are broken.
  def resolve_target(path)
    return path.to_s unless path.symlink?

    path.realpath.to_s
  rescue Errno::ENOENT
    path.readlink.to_s
  end

  # Formats ownership and permission metadata for diagnostics.
  # We include owner/group/mode because most install failures here are permission-related,
  # and users need concrete data to fix local filesystem ownership issues.
  def path_metadata(path)
    stat = path.lstat
    owner = begin
      Etc.getpwuid(stat.uid).name
    rescue ArgumentError
      stat.uid.to_s
    end
    group = begin
      Etc.getgrgid(stat.gid).name
    rescue ArgumentError
      stat.gid.to_s
    end
    mode = format("%03o", stat.mode & 0o777)
    "#{path} owner=#{owner}:#{group} mode=#{mode}"
  rescue Errno::ENOENT
    "#{path} (missing)"
  end

  # User-facing guidance when we cannot even attempt deletion because the directory
  # containing `bin/solo` is not writable by the current user.
  def stale_entry_permission_guidance(brew_bin_solo, brew_install_cmd)
    <<~EOS
      ATTENTION: Cannot remove #{brew_bin_solo}; #{brew_bin_solo.dirname} is not writable by the current user.
      Directory details: #{path_metadata(brew_bin_solo.dirname)}
      Entry details: #{path_metadata(brew_bin_solo)}
      Please remove it before installing:
        rm '#{brew_bin_solo}'
      If you see a permissions error, try:
        sudo rm '#{brew_bin_solo}'
      Then re-run: #{brew_install_cmd}
    EOS
  end

  # User-facing guidance when deletion was attempted but failed (EPERM/EACCES).
  # Includes both the Ruby error message and path metadata for quick triage.
  def stale_entry_remove_failed_guidance(brew_bin_solo, brew_install_cmd, error)
    <<~EOS
      ATTENTION: Unable to remove #{brew_bin_solo}: #{error.message}
      Directory details: #{path_metadata(brew_bin_solo.dirname)}
      Entry details: #{path_metadata(brew_bin_solo)}
      Please remove it before installing:
        rm '#{brew_bin_solo}'
      If you see a permissions error, try:
        sudo rm '#{brew_bin_solo}'
      Then re-run: #{brew_install_cmd}
    EOS
  end

  def install
    # Step 0: Validate environment prerequisites before modifying the system.
    odie "npm was not found in PATH; install Node.js first." if which("npm").nil?

    # Derive the full brew install command from the formula's own tap/name so it stays accurate
    # if the tap is ever renamed, and to avoid duplicating the string in every error message.
    brew_install_cmd = tap ? "brew install #{tap.name}/#{name}" : "brew install hiero-ledger/tools/solo"

    # Step 1: Remove any non-Homebrew solo binary/symlink to avoid link conflicts.
    brew_bin_solo = HOMEBREW_PREFIX/"bin/solo"
    if brew_bin_solo.exist?
      # Resolve the effective target (works for both valid and dangling symlinks).
      target = resolve_target(brew_bin_solo)
      unless homebrew_managed_solo_target?(target)
        entry_type = brew_bin_solo.symlink? ? "symlink" : "binary"
        opoo <<~EOS
          ATTENTION: Found a non-Homebrew solo #{entry_type} at #{brew_bin_solo}.
          Target: #{target}
          Removing it to avoid conflicts with the Homebrew install.
        EOS

        # Fail early with explicit guidance if we do not have directory-level write permissions.
        odie stale_entry_permission_guidance(brew_bin_solo, brew_install_cmd) unless brew_bin_solo.dirname.writable?

        begin
          # Remove stale symlink or stale regular file using the appropriate operation.
          if brew_bin_solo.symlink?
            brew_bin_solo.unlink
          else
            brew_bin_solo.delete
          end
        rescue Errno::EPERM, Errno::EACCES => e
          odie stale_entry_remove_failed_guidance(brew_bin_solo, brew_install_cmd, e)
        end
      end
    end

    # Step 2: Detect and remove global npm links/installations that conflict with Homebrew.
    npm_packages = ["@hiero-ledger/solo", "@hashgraph/solo"]
    # Ignore external NPM_CONFIG_PREFIX so we inspect the effective global npm root
    # used by the current runtime environment.
    npm_env = {"NPM_CONFIG_PREFIX" => nil}
    npm_root = Utils.popen_read(npm_env, "npm", "root", "-g").strip
    brew_prefix_root = (HOMEBREW_PREFIX/"lib/node_modules").to_s

    # Pass A: remove global npm symlinks (`npm link`) for supported package names.
    npm_packages.each do |pkg|
      pkg_scope, pkg_name = pkg.split("/")
      pkg_path = File.join(npm_root, pkg_scope, pkg_name)
      brew_pkg_path = File.join(brew_prefix_root, pkg_scope, pkg_name)

      if !npm_root.empty? && File.symlink?(pkg_path)
        opoo <<~EOS
          ATTENTION: Detected a global npm link for #{pkg}.
          Removing it to avoid conflicts with the Homebrew install.
        EOS
        begin
          system "npm", "unlink", "-g", pkg
        rescue BuildError
          opoo <<~EOS
            ATTENTION: Unable to unlink npm link for #{pkg}.
            Please run: npm unlink -g #{pkg}
            If you see a permissions error, try:
              sudo chown -R "$(whoami)" #{HOMEBREW_PREFIX}/lib/node_modules
              sudo npm unlink -g #{pkg}
          EOS
        end

        if File.symlink?(pkg_path)
          opoo <<~EOS
            ATTENTION: npm link for #{pkg} is still present.
            Please remove it manually: npm unlink -g #{pkg}
          EOS
        else
          ohai "Removed npm link for #{pkg}."
        end
      end
    end

    # Pass B: remove global npm physical installs, both in npm root and Homebrew prefix.
    npm_packages.each do |pkg|
      pkg_scope, pkg_name = pkg.split("/")
      pkg_path = File.join(npm_root, pkg_scope, pkg_name)
      brew_pkg_path = File.join(brew_prefix_root, pkg_scope, pkg_name)
      if !npm_root.empty? && File.exist?(pkg_path) && !File.symlink?(pkg_path)
        opoo <<~EOS
          ATTENTION: Detected a global npm install for #{pkg}.
          Attempting to uninstall to avoid conflicts with the Homebrew install.
        EOS
        begin
          system "npm", "uninstall", "-g", pkg
          ohai "Removed global npm install for #{pkg}."
        rescue BuildError
          opoo <<~EOS
            ATTENTION: Detected a global npm install of #{pkg} that could not be removed.
            Please run: npm uninstall -g #{pkg}
            If you see a permissions error, try:
              sudo chown -R "$(whoami)" #{HOMEBREW_PREFIX}/lib/node_modules
              sudo npm uninstall -g #{pkg}
          EOS
        end
      end

      if File.exist?(brew_pkg_path) && !File.symlink?(brew_pkg_path)
        opoo <<~EOS
          ATTENTION: Detected a global npm install for #{pkg} under #{brew_prefix_root}.
          Attempting to uninstall to avoid conflicts with the Homebrew install.
        EOS
        begin
          system "npm", "uninstall", "-g", "--prefix", HOMEBREW_PREFIX.to_s, pkg
          ohai "Removed npm install for #{pkg} under #{brew_prefix_root}."
        rescue BuildError
          opoo <<~EOS
            ATTENTION: Detected a global npm install of #{pkg} under #{brew_prefix_root} that could not be removed.
            Please run: npm uninstall -g --prefix #{HOMEBREW_PREFIX} #{pkg}
            If you see a permissions error, try:
              sudo chown -R "$(whoami)" #{HOMEBREW_PREFIX}/lib/node_modules
              sudo npm uninstall -g --prefix #{HOMEBREW_PREFIX} #{pkg}
          EOS
        end
      end
    end

    # Step 3: Install the Homebrew-managed npm package and expose the binary.
    system "npm", "install", *std_npm_args
    bin.install_symlink Dir["#{libexec}/bin/*"]
  end

  def post_install
    # Step 4: Guard against any lingering non-Homebrew solo binary after install.
    # This catches edge cases where an external process recreates the stale entry during install.
    brew_bin_solo = HOMEBREW_PREFIX/"bin/solo"
    return unless brew_bin_solo.exist?

    target = resolve_target(brew_bin_solo)
    return if homebrew_managed_solo_target?(target)

    odie <<~EOS
      ATTENTION: Found an existing solo binary at #{brew_bin_solo}.
      Target: #{target}
      Please remove it before installing: rm '#{brew_bin_solo}'
      Alternatively: brew link --overwrite solo
    EOS
  end

  test do
    assert_match(/^Usage:\s+solo\b/m, shell_output("#{bin}/solo --help"))
  end
end
