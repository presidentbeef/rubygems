require 'rubygems/test_case'
require 'rubygems/commands/install_command'

class TestGemCommandsInstallCommand < Gem::TestCase

  def setup
    super

    @cmd = Gem::Commands::InstallCommand.new
    @cmd.options[:document] = []
  end

  def test_execute_exclude_prerelease
    util_setup_fake_fetcher :prerelease
    util_setup_spec_fetcher

    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      read_binary(@a2.cache_file)
    @fetcher.data["#{@gem_repo}gems/#{@a2_pre.file_name}"] =
      read_binary(@a2_pre.cache_file)

    @cmd.options[:args] = [@a2.name]

    use_ui @ui do
      e = assert_raises Gem::SystemExitException do
        @cmd.execute
      end
      assert_equal 0, e.exit_code, @ui.error
    end

    assert_equal %w[a-2], @cmd.installed_specs.map { |spec| spec.full_name }
  end

  def test_execute_explicit_version_includes_prerelease
    util_setup_fake_fetcher :prerelease
    util_setup_spec_fetcher

    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      read_binary(@a2.cache_file)
    @fetcher.data["#{@gem_repo}gems/#{@a2_pre.file_name}"] =
      read_binary(@a2_pre.cache_file)

    @cmd.handle_options [@a2_pre.name, '--version', @a2_pre.version.to_s,
                         "--no-ri", "--no-rdoc"]
    assert @cmd.options[:prerelease]
    assert @cmd.options[:version].satisfied_by?(@a2_pre.version)

    use_ui @ui do
      e = assert_raises Gem::SystemExitException do
        @cmd.execute
      end
      assert_equal 0, e.exit_code, @ui.error
    end

    assert_equal %w[a-2.a], @cmd.installed_specs.map { |spec| spec.full_name }
  end

  def test_execute_include_dependencies
    @cmd.options[:include_dependencies] = true
    @cmd.options[:args] = []

    assert_raises Gem::CommandLineError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal %w[], @cmd.installed_specs.map { |spec| spec.full_name }

    output = @ui.output.split "\n"
    assert_equal "INFO:  `gem install -y` is now default and will be removed",
                 output.shift
    assert_equal "INFO:  use --ignore-dependencies to install only the gems you list",
                 output.shift
    assert output.empty?, output.inspect
  end

  def test_execute_local
    util_setup_fake_fetcher
    @cmd.options[:domain] = :local

    FileUtils.mv @a2.cache_file, @tempdir

    @cmd.options[:args] = [@a2.name]

    use_ui @ui do
      orig_dir = Dir.pwd
      begin
        Dir.chdir @tempdir
        e = assert_raises Gem::SystemExitException do
          @cmd.execute
        end
        assert_equal 0, e.exit_code
      ensure
        Dir.chdir orig_dir
      end
    end

    assert_equal %w[a-2], @cmd.installed_specs.map { |spec| spec.full_name }

    out = @ui.output.split "\n"
    assert_equal "1 gem installed", out.shift
    assert out.empty?, out.inspect
  end

  def test_execute_no_user_install
    skip 'skipped on MS Windows (chmod has no effect)' if win_platform?

    util_setup_fake_fetcher
    @cmd.options[:user_install] = false

    FileUtils.mv @a2.cache_file, @tempdir

    @cmd.options[:args] = [@a2.name]

    use_ui @ui do
      orig_dir = Dir.pwd
      begin
        FileUtils.chmod 0755, @userhome
        FileUtils.chmod 0555, @gemhome

        Dir.chdir @tempdir
        assert_raises Gem::FilePermissionError do
          @cmd.execute
        end
      ensure
        Dir.chdir orig_dir
        FileUtils.chmod 0755, @gemhome
      end
    end
  end

  def test_execute_local_missing
    util_setup_fake_fetcher
    @cmd.options[:domain] = :local

    @cmd.options[:args] = %w[no_such_gem]

    use_ui @ui do
      e = assert_raises Gem::SystemExitException do
        @cmd.execute
      end
      assert_equal 2, e.exit_code
    end

    # HACK no repository was checked
    assert_match(/ould not find a valid gem 'no_such_gem'/, @ui.error)
  end

  def test_execute_no_gem
    @cmd.options[:args] = %w[]

    assert_raises Gem::CommandLineError do
      @cmd.execute
    end
  end

  def test_execute_nonexistent
    util_setup_fake_fetcher
    util_setup_spec_fetcher

    @cmd.options[:args] = %w[nonexistent]

    use_ui @ui do
      e = assert_raises Gem::SystemExitException do
        @cmd.execute
      end
      assert_equal 2, e.exit_code
    end

    assert_match(/ould not find a valid gem 'nonexistent'/, @ui.error)
  end

  def test_execute_nonexistent_with_hint
    misspelled = "nonexistent_with_hint"
    correctly_spelled = "non_existent_with_hint"

    util_setup_fake_fetcher
    util_setup_spec_fetcher quick_spec(correctly_spelled, '2')

    @cmd.options[:args] = [misspelled]

    use_ui @ui do
      e = assert_raises Gem::SystemExitException do
        @cmd.execute
      end

      assert_equal 2, e.exit_code
    end

    expected = "ERROR:  Could not find a valid gem 'nonexistent_with_hint' (>= 0) in any repository
ERROR:  Possible alternatives: non_existent_with_hint
"

    assert_equal expected, @ui.error
  end

  def test_execute_conflicting_install_options
    @cmd.options[:user_install] = true
    @cmd.options[:install_dir] = "whatever"

    use_ui @ui do
      assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end
    end

    expected = "ERROR:  Use --install-dir or --user-install but not both\n"

    assert_equal expected, @ui.error
  end

  def test_execute_prerelease
    util_setup_fake_fetcher :prerelease
    util_clear_gems
    util_setup_spec_fetcher @a2, @a2_pre

    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      read_binary(@a2.cache_file)
    @fetcher.data["#{@gem_repo}gems/#{@a2_pre.file_name}"] =
      read_binary(@a2_pre.cache_file)

    @cmd.options[:prerelease] = true
    @cmd.options[:args] = [@a2_pre.name]

    use_ui @ui do
      e = assert_raises Gem::SystemExitException do
        @cmd.execute
      end
      assert_equal 0, e.exit_code, @ui.error
    end

    assert_equal %w[a-2.a], @cmd.installed_specs.map { |spec| spec.full_name }
  end

  def test_execute_rdoc
    util_setup_fake_fetcher

    Gem.done_installing(&Gem::RDoc.method(:generation_hook))

    @cmd.options[:document] = %w[rdoc ri]
    @cmd.options[:domain] = :local

    FileUtils.mv @a2.cache_file, @tempdir

    @cmd.options[:args] = [@a2.name]

    use_ui @ui do
      # Don't use Dir.chdir with a block, it warnings a lot because
      # of a downstream Dir.chdir with a block
      old = Dir.getwd

      begin
        Dir.chdir @tempdir
        e = assert_raises Gem::SystemExitException do
          @cmd.execute
        end
      ensure
        Dir.chdir old
      end

      assert_equal 0, e.exit_code
    end

    assert_path_exists File.join(@a2.doc_dir, 'ri')
    assert_path_exists File.join(@a2.doc_dir, 'rdoc')
  end

  def test_execute_remote
    util_setup_fake_fetcher
    util_setup_spec_fetcher

    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      read_binary(@a2.cache_file)

    @cmd.options[:args] = [@a2.name]

    use_ui @ui do
      e = assert_raises Gem::SystemExitException do
        capture_io do
          @cmd.execute
        end
      end
      assert_equal 0, e.exit_code
    end

    assert_equal %w[a-2], @cmd.installed_specs.map { |spec| spec.full_name }

    out = @ui.output.split "\n"
    assert_equal "1 gem installed", out.shift
    assert out.empty?, out.inspect
  end

  def test_execute_remote_ignores_files
    util_setup_fake_fetcher
    util_setup_spec_fetcher

    @cmd.options[:domain] = :remote

    FileUtils.mv @a2.cache_file, @tempdir

    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      read_binary(@a1.cache_file)

    @cmd.options[:args] = [@a2.name]

    gemdir     = File.join @gemhome, 'specifications'

    a2_gemspec = File.join(gemdir, "a-2.gemspec")
    a1_gemspec = File.join(gemdir, "a-1.gemspec")

    FileUtils.rm_rf a1_gemspec
    FileUtils.rm_rf a2_gemspec

    start = Dir["#{gemdir}/*"]

    use_ui @ui do
      Dir.chdir @tempdir do
        e = assert_raises Gem::SystemExitException do
          @cmd.execute
        end
        assert_equal 0, e.exit_code
      end
    end

    assert_equal %w[a-1], @cmd.installed_specs.map { |spec| spec.full_name }

    out = @ui.output.split "\n"
    assert_equal "1 gem installed", out.shift
    assert out.empty?, out.inspect

    fin = Dir["#{gemdir}/*"]

    assert_equal [a1_gemspec], fin - start
  end

  def test_execute_two
    util_setup_fake_fetcher
    @cmd.options[:domain] = :local

    FileUtils.mv @a2.cache_file, @tempdir

    FileUtils.mv @b2.cache_file, @tempdir

    @cmd.options[:args] = [@a2.name, @b2.name]

    use_ui @ui do
      orig_dir = Dir.pwd
      begin
        Dir.chdir @tempdir
        e = assert_raises Gem::SystemExitException do
          @cmd.execute
        end
        assert_equal 0, e.exit_code
      ensure
        Dir.chdir orig_dir
      end
    end

    assert_equal %w[a-2 b-2], @cmd.installed_specs.map { |spec| spec.full_name }

    out = @ui.output.split "\n"
    assert_equal "2 gems installed", out.shift
    assert out.empty?, out.inspect
  end

  def test_execute_conservative
    util_setup_fake_fetcher
    util_setup_spec_fetcher

    @fetcher.data["#{@gem_repo}gems/#{@b2.file_name}"] =
      read_binary(@b2.cache_file)

    uninstall_gem(@b2)

    @cmd.options[:conservative] = true

    @cmd.options[:args] = [@a2.name, @b2.name]

    use_ui @ui do
      orig_dir = Dir.pwd
      begin
        Dir.chdir @tempdir
        assert_raises Gem::SystemExitException do
          @cmd.execute
        end
      ensure
        Dir.chdir orig_dir
      end
    end

    assert_equal %w[b-2], @cmd.installed_specs.map { |spec| spec.full_name }

    out = @ui.output.split "\n"
    assert_equal "", @ui.error
    assert_equal "1 gem installed", out.shift
    assert out.empty?, out.inspect
  end

  #Checks the case where one remote source works fine
  #but the other contains only specs*.gz and latest_specs*.gz,
  #no individual specs or gems
  def test_execute_one_failing_gem_source

    assert_failing_server do |specs, bad_repo|
      specs_dump_gz = StringIO.new
      Zlib::GzipWriter.wrap specs_dump_gz do |io|
        Marshal.dump specs, io
      end

      @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      read_binary(@a2.cache_file)

      @fetcher.data["#{bad_repo}/specs.#{@marshal_version}.gz"] =
      specs_dump_gz.string

      @fetcher.data["#{bad_repo}/latest_specs.#{@marshal_version}.gz"] =
      specs_dump_gz.string
    end
  end

  #Check that gem can still be installed even if one of the known sources
  #is not available
  def test_execute_one_failing_source
    assert_failing_server do |specs, bad_repo|
      #If the source was added, then the specs file should exist locally
      #Sources cannot be added unless they exist at the time
      write_file("#{@userhome}/.gem/specs/gems2.example.com%80/latest_specs.4.8") do |file|
        Marshal.dump specs, file
      end
    end
  end

  #Set up gem sources but with one source that is not actually available
  def assert_failing_server
    util_setup_fake_fetcher
    util_setup_spec_fetcher

    #Add the failing source
    new_repo = "http://gems2.example.com"
    Gem.sources << new_repo

    specs = Gem::Specification.map { |spec|
      [spec.name, spec.version, spec.original_platform]
    }

    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      read_binary(@a2.cache_file)

    yield specs, new_repo

    @cmd.options[:args]  = [@a2.name]

    use_ui @ui do
      orig_dir = Dir.pwd
      begin
        Dir.chdir @tempdir
        e = assert_raises Gem::SystemExitException do
          @cmd.execute
        end
        assert_equal 0, e.exit_code
      ensure
        Dir.chdir orig_dir
      end
    end

    assert_equal "1 gem installed\n", @ui.output
    assert_equal "", @ui.error
  end
end

