class Solo < Formula
  desc "An opinionated CLI tool to deploy and manage standalone test networks."
  homepage "https://github.com/hiero-ledger/solo"

  url "https://registry.npmjs.org/@hashgraph/solo/-/solo-0.72.0.tgz"
  sha256 "6b4d1cd6645448154ecd916ab14ff5e1434d7df349ae53d18761942413e5ded3"
  version "0.72.0"

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
          opoo <<~EOS
            ATTENTION: Found a stale or non-Homebrew solo symlink at #{brew_bin_solo}.
            Target: #{target}
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
        opoo <<~EOS
          ATTENTION: Found a non-Homebrew solo binary at #{brew_bin_solo}.
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

    # Step 2: Detect and remove global npm links/installations that conflict with Homebrew.
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

    # Step 3: Install the Homebrew-managed npm package and expose the binary.
    # Export system CA certificates so npm can trust enterprise/corporate CA certificates
    # used by SSL inspection proxies (e.g., Zscaler, Cisco Umbrella).
    npm_install_env = {}
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
  end

  def post_install
    # Step 4: Guard against any lingering non-Homebrew solo binary after install.
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

  test do
    assert_match(/^Usage:\s+solo\b/m, shell_output("#{bin}/solo --help"))
  end
end
