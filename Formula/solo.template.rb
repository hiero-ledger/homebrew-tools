class Solo < Formula
  desc "An opinionated CLI tool to deploy and manage standalone test networks."
  homepage "https://github.com/hiero-ledger/solo"

  url "https://registry.npmjs.org/@hashgraph/solo/-/solo-__SOLO_VERSION__.tgz"
  sha256 "__SOLO_SHA256__"
  version "__SOLO_VERSION__"

  depends_on "node"
  link_overwrite "bin/solo"

  def install
    # Step 0: Validate environment prerequisites before modifying the system.
    odie "npm was not found in PATH; install Node.js first." if which("npm").nil?

    # Derive the full brew install command from the formula's own tap/name so it stays accurate
    # if the tap is ever renamed, and to avoid duplicating the string in every error message.
    brew_install_cmd = tap ? "brew install #{tap.name}/#{name}" : "brew install hiero-ledger/tools/solo"

    # Step 1: Remove any non-Homebrew solo binary/symlink to avoid link conflicts.
    brew_bin_solo = HOMEBREW_PREFIX/"bin/solo"
    # Check both exist? and symlink? because exist? is false for broken symlinks.
    if brew_bin_solo.exist? || brew_bin_solo.symlink?
      if brew_bin_solo.symlink?
        stale_symlink = false
        target = begin
          brew_bin_solo.realpath.to_s
        rescue Errno::ENOENT
          stale_symlink = true
          brew_bin_solo.readlink.to_s
        end
        allow_prefixes = [
          (HOMEBREW_PREFIX/"Cellar/solo").to_s,
          (HOMEBREW_PREFIX/"opt/solo").to_s,
        ]
        managed_by_homebrew = allow_prefixes.any? { |prefix| target.start_with?(prefix) }
        should_remove_symlink = stale_symlink || !managed_by_homebrew

        if should_remove_symlink
          old_version = detect_solo_version_at(target)
          opoo <<~EOS
            ATTENTION: Will remove existing solo installation.
            Path: #{brew_bin_solo}
            Target: #{target}
            Version to remove: #{old_version}
            Removing it to avoid conflicts with the Homebrew install.
          EOS

          begin
            brew_bin_solo.unlink
          rescue Errno::EPERM, Errno::EACCES => e
            opoo <<~EOS
              Could not remove #{brew_bin_solo} in sandbox (#{e.message}).
              The link_overwrite directive will handle this during the linking phase.
            EOS
          end
        end
      else
        old_version = detect_solo_version_at(brew_bin_solo.to_s)
        opoo <<~EOS
          ATTENTION: Will remove existing solo installation.
          Path: #{brew_bin_solo}
          Version to remove: #{old_version}
          Removing it to avoid conflicts with the Homebrew install.
        EOS

        if brew_bin_solo.dirname.writable?
          begin
            brew_bin_solo.delete
          rescue Errno::EPERM, Errno::EACCES => e
            odie <<~EOS
              ATTENTION: Unable to remove #{brew_bin_solo}: #{e.message}
              Please remove it before installing:
                rm '#{brew_bin_solo}'
              If you see a permissions error, try:
                sudo rm '#{brew_bin_solo}'
              Then re-run: #{brew_install_cmd}
            EOS
          end
        else
          odie <<~EOS
            ATTENTION: Cannot remove #{brew_bin_solo}; #{brew_bin_solo.dirname} is not writable.
            Please remove it before installing:
              rm '#{brew_bin_solo}'
            If you see a permissions error, try:
              sudo rm '#{brew_bin_solo}'
            Then re-run: #{brew_install_cmd}
          EOS
        end
      end
    end

    # Step 2: Find and remove ALL solo binaries in PATH (npm global, nvm, custom prefixes, etc.).
    solo_binaries_in_path = `which -a solo 2>/dev/null`.strip.split("\n").reject(&:empty?)
    brew_solo_path = (HOMEBREW_PREFIX/"bin/solo").to_s
    solo_binaries_in_path.each do |solo_path|
      next if solo_path == brew_solo_path
      next if solo_path.start_with?((HOMEBREW_PREFIX/"Cellar/solo").to_s)
      next if solo_path.start_with?((HOMEBREW_PREFIX/"opt/solo").to_s)

      old_version = detect_solo_version_at(solo_path)
      if nvm_managed_solo_path?(solo_path)
        npm_prefix = File.expand_path("..", File.dirname(solo_path))
        opoo <<~EOS
          ============================================================================
          IMPORTANT: NVM-MANAGED SOLO DETECTED (MANUAL ACTION REQUIRED)
          ============================================================================
          ATTENTION: Found existing nvm-managed solo installation.
          Path: #{solo_path}
          Version detected: #{old_version}
          Homebrew does not automatically remove nvm-managed binaries during formula install.
          Please remove it manually before installing:
            npm uninstall -g --prefix #{npm_prefix} @hashgraph/solo
            npm uninstall -g --prefix #{npm_prefix} @hiero-ledger/solo
          Note: after install, follow the `hash -r` verification steps shown in Caveats.
        EOS
        next
      end

      opoo <<~EOS
        ATTENTION: Will remove existing solo installation.
        Path: #{solo_path}
        Version to remove: #{old_version}
        Attempting to remove it to avoid PATH conflicts.
      EOS

      # Determine if it's an npm installation by checking standard npm global layout.
      solo_dir = File.dirname(solo_path)
      npm_prefix = File.expand_path("..", solo_dir)
      node_modules_parent = File.join(npm_prefix, "lib/node_modules")

      if File.directory?(node_modules_parent)
        npm_packages = ["@hiero-ledger/solo", "@hashgraph/solo"]
        npm_packages.each do |pkg|
          pkg_path = File.join(node_modules_parent, pkg)
          next unless File.exist?(pkg_path)

          begin
            # Try to uninstall using the npm prefix that matches this installation.
            system "npm", "uninstall", "-g", "--prefix", npm_prefix, pkg
            ohai "Removed #{pkg} from #{npm_prefix}."
          rescue BuildError
            opoo <<~EOS
              ATTENTION: Could not automatically remove #{pkg} at #{pkg_path}.
              Please remove manually: npm uninstall -g --prefix #{npm_prefix} #{pkg}
            EOS
          end
        end
      else
        opoo <<~EOS
          ATTENTION: Found solo binary at #{solo_path} that is not managed by npm or Homebrew.
          Please remove it manually before installing:
            rm '#{solo_path}'
        EOS
      end
    end

    # Step 2b: Detect nvm-managed solo installs and provide manual cleanup guidance.
    detect_nvm_solo_paths.each do |solo_path|
      old_version = detect_solo_version_at(solo_path)
      npm_prefix = File.expand_path("..", File.dirname(solo_path))
      opoo <<~EOS
        ============================================================================
        IMPORTANT: NVM-MANAGED SOLO DETECTED (MANUAL ACTION REQUIRED)
        ============================================================================
        ATTENTION: Found existing nvm-managed solo installation.
        Path: #{solo_path}
        Version detected: #{old_version}
        Homebrew does not automatically remove nvm-managed binaries during formula install.
        Please remove it manually before installing:
          npm uninstall -g --prefix #{npm_prefix} @hashgraph/solo
          npm uninstall -g --prefix #{npm_prefix} @hiero-ledger/solo
        Note: after install, follow the `hash -r` verification steps shown in Caveats.
      EOS
    end

    # Step 3: Detect and remove global npm links/installations from default npm root.
    npm_packages = ["@hiero-ledger/solo", "@hashgraph/solo"]
    npm_env = {"NPM_CONFIG_PREFIX" => nil}
    npm_root = Utils.popen_read(npm_env, "npm", "root", "-g").strip
    brew_prefix_root = (HOMEBREW_PREFIX/"lib/node_modules").to_s

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

    # Step 4: Install the Homebrew-managed npm package and expose the binary.
    # Export system CA certificates so npm can trust enterprise/corporate CA certificates
    # used by SSL inspection proxies (e.g., Zscaler, Cisco Umbrella).
    npm_install_env = {}
    npm_install_env["SOLO_NO_CACHE"] = "true" if ENV.key?("HOMEBREW_NO_SOLO_CACHE")
    if OS.mac?
      ca_bundle = buildpath/"ca-bundle.pem"
      [
        "/System/Library/Keychains/SystemRootCertificates.keychain",
        "/Library/Keychains/System.keychain",
      ].each do |kc|
        next unless File.exist?(kc)

        pem = Utils.popen_read("/usr/bin/security", "find-certificate", "-a", "-p", kc)
        File.open(ca_bundle, "a") { |f| f.write(pem) } unless pem.empty?
      end
      npm_install_env["NODE_EXTRA_CA_CERTS"] = ca_bundle.to_s if ca_bundle.exist?
    elsif OS.linux?
      linux_ca_paths = [
        "/etc/ssl/certs/ca-certificates.crt",
        "/etc/pki/tls/certs/ca-bundle.crt",
        "/etc/ssl/ca-bundle.pem",
        "/etc/pki/tls/cacert.pem",
      ]
      ca_path = linux_ca_paths.find { |p| File.exist?(p) }
      npm_install_env["NODE_EXTRA_CA_CERTS"] = ca_path if ca_path
    end

    with_env(npm_install_env) do
      system "npm", "install", *std_npm_args
    end
    bin.install_symlink Dir["#{libexec}/bin/*"]

    # Step 4b: Warm default Solo images to reduce first-run setup time.
    pull_default_cache_images unless ENV.key?("HOMEBREW_NO_SOLO_CACHE")
  end

  def post_install
    # Step 5: Guard against any lingering non-Homebrew solo binary after install.
    brew_bin_solo = HOMEBREW_PREFIX/"bin/solo"
    return unless brew_bin_solo.exist? || brew_bin_solo.symlink?

    target = if brew_bin_solo.symlink?
      begin
        brew_bin_solo.realpath.to_s
      rescue Errno::ENOENT
        brew_bin_solo.readlink.to_s
      end
    else
      brew_bin_solo.to_s
    end
    allow_prefixes = [
      (HOMEBREW_PREFIX/"Cellar/solo").to_s,
      (HOMEBREW_PREFIX/"opt/solo").to_s,
    ]

    return if allow_prefixes.any? { |prefix| target.start_with?(prefix) }

    odie <<~EOS
      ATTENTION: Found an existing solo binary at #{brew_bin_solo}.
      Target: #{target}
      Please remove it before installing: rm '#{brew_bin_solo}'
      Alternatively: brew link --overwrite solo
    EOS
  end

  def caveats
    <<~EOS
      If `solo` still resolves to an old path after install, your shell may be using a cached command path.
      Refresh your shell command cache:
        hash -r
      Then verify:
        command -v solo
        solo --version
    EOS
  end

  private

  def pull_default_cache_images
    solo_bin = libexec/"bin/solo"
    unless solo_bin.exist?
      opoo "Skipped `solo cache image pull`: #{solo_bin} was not found."
      return
    end

    require "open3"

    timeout_seconds = Integer(ENV.fetch("HOMEBREW_SOLO_CACHE_PULL_TIMEOUT", "1800"))
    timeout_seconds = 1800 if timeout_seconds <= 0
    progress_interval_seconds = 30
    started_at = Time.now
    last_progress_log_at = started_at
    status = nil
    timed_out = false

    ohai "Pre-pulling default Solo cache images..."
    Open3.popen2e(solo_bin.to_s, "cache", "image", "pull") do |_stdin, output, wait_thread|
      loop do
        chunk = output.read_nonblock(4096, exception: false)
        case chunk
        when :wait_readable
          elapsed_seconds = (Time.now - started_at).to_i
          if elapsed_seconds >= timeout_seconds
            timed_out = true
            Process.kill("TERM", wait_thread.pid) rescue Errno::ESRCH
            sleep 2
            Process.kill("KILL", wait_thread.pid) rescue Errno::ESRCH
            status = wait_thread.value
            break
          end

          if (Time.now - last_progress_log_at) >= progress_interval_seconds
            ohai "Still pre-pulling Solo cache images... #{elapsed_seconds}s elapsed."
            last_progress_log_at = Time.now
          end

          sleep 1
        when nil
          status = wait_thread.value
          break
        else
          print chunk
        end
      end
    end

    if timed_out
      opoo <<~EOS
        ATTENTION: `solo cache image pull` timed out after #{timeout_seconds}s.
        Homebrew install will continue. You can retry manually any time with:
          solo cache image pull
      EOS
      return
    end

    unless status&.success?
      opoo <<~EOS
        ATTENTION: `solo cache image pull` exited with status #{status&.exitstatus || "unknown"}.
        Homebrew install will continue. You can retry manually any time with:
          solo cache image pull
      EOS
      return
    end

    ohai "Completed `solo cache image pull`."
  rescue StandardError => e
    opoo <<~EOS
      ATTENTION: Could not pre-pull Solo cache images during install (#{e.message}).
      You can run it manually any time with:
        solo cache image pull
    EOS
  end

  def detect_solo_version_at(path)
    return "unknown" if path.to_s.empty?
    return "unknown" unless File.exist?(path) || File.symlink?(path)

    version_output = Utils.safe_popen_read(path, "--version").strip
    version_output.empty? ? "unknown" : version_output
  rescue StandardError
    "unknown"
  end

  def nvm_managed_solo_path?(path)
    path.include?("/.nvm/versions/node/") && path.end_with?("/bin/solo")
  end

  def detect_nvm_solo_paths
    require "etc"

    user_home_candidates = [
      ENV["HOMEBREW_ORIGINAL_HOME"],
      Etc.getpwuid(Process.uid).dir,
      Dir.home,
      ENV["HOME"],
    ].compact.uniq

    paths = []
    user_home_candidates.each do |home|
      nvm_root = File.join(home, ".nvm")
      next unless File.directory?(nvm_root)

      Dir.glob(File.join(nvm_root, "versions/node/*/bin/solo")).each do |solo_path|
        paths << solo_path if File.exist?(solo_path) || File.symlink?(solo_path)
      end
    end

    paths.uniq
  rescue StandardError
    []
  end

  test do
    assert_match(/^Usage:\s+solo\b/m, shell_output("#{bin}/solo --help"))
  end
end
