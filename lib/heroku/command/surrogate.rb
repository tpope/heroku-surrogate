# run commands locally using the remote environment
class Heroku::Command::Surrogate < Heroku::Command::Base

  # surrogate [OVERRIDE1=VALUE1 ...] COMMAND
  #
  # run COMMAND locally using environment variables from the app config
  #
  # --release RELEASE # use environment at time of RELEASE
  # --checkout        # git checkout the release commit first
  #
  # All environment variables from the application config except for those
  # ending in PATH will be merged into the current environment before
  # execution.
  #
  #Examples:
  #
  #   $ heroku surrogate env
  #   $ heroku surrogate rake db:version
  #   $ heroku surrogate console
  #   $ heroku surrogate PORT=3000 web
  #   $ heroku surrogate $SHELL
  def index
    if options[:release]
      release = api.get_release(app, options[:release]).body
    else
      release = api.get_releases(app).body.last
    end

    vars = release['env']

    vars.delete_if do |k, v|
      k =~ /PATH$/
    end

    while args.any? && args.first.include?('=')
      k, v = *args.shift.split('=', 2)
      vars[k] = v
    end

    command = ''
    if args.empty?
      error("Usage: heroku surrogate [OVERRIDE1=VALUE1 ...] COMMAND\nMust specify COMMAND")
    elsif release['pstable'].has_key?(args.first)
      command << release['pstable'][args.shift] << ' '
    end

    require 'shellwords'
    command << args.map { |a| Shellwords.escape(a) }.join(' ')

    if command =~ TEST_SUITE_CHECK
      error("Refusing to run the test suite against live data")
    end

    if options[:checkout]
      if git("rev-parse --quiet --verify #{release['commit']}").empty?
        git("fetch #{api.get_app(app).body['git_url']}")
      end
      system("git checkout #{release['commit']} --") or exit 1
    end

    ENV.update(vars)
    exec(command)
  end

  TEST_SUITE_CHECK = %r{
    \A\s*
    (?:bundle\s+exec\s+|bin/)?
    (?:
      rake\s*(?:\z|.*\s(?:test|spec|cucumber|features))
      |testrb\b|rspec\b|cucumber\b
    )
  }x

end
