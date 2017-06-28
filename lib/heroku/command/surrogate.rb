require 'net/http'
require 'stringio'
require 'json'

# run commands locally using the remote environment
class Heroku::Command::Surrogate < Heroku::Command::Base

  # surrogate [OVERRIDE1=VALUE1 ...] COMMAND [...]
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
    release = get_release(app, options[:release])

    vars = release['env'].inject({}) do |m, (k, v)|
      m.update(k => v.to_s)
    end

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

    if args.size == 1 && command.empty?
      command << args.first
    else
      require 'shellwords'
      command << args.map { |a| Shellwords.escape(a) }.join(' ')
    end

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

private

  def get_release(app, release_id = nil)
    release = get_release_info(app, release_id)
    env     = Thread.new { get_config_vars(app, release['id']) }
    pstable = Thread.new { get_pstable(app, release['slug']['id']) }

    release.merge('env' => env.value, 'pstable' => pstable.value)
  end

  def get_config_vars(app, release_id)
    api_request("/apps/#{URI.escape(app)}/releases/#{URI.escape(release_id)}/config-vars")
  end

  def get_pstable(app, slug_id)
    api_request("/apps/#{URI.escape(app)}/slugs/#{URI.escape(slug_id)}").fetch("process_types", {})
  end

  def get_release_info(app, release_id = nil)
    api_path = "/apps/#{URI.escape(app)}/releases"
    api_path << "/#{URI.escape(release_id)}" if release_id
    response_data = api_request(api_path)
    release_id ? response_data : response_data.last
  end

  def api_request(api_path)
    uri = URI("https://api.heroku.com") + api_path
    req = Net::HTTP::Get.new uri
    req['Accept'] = "application/vnd.heroku+json; version=3"
    req['Authorization'] = "Bearer #{Heroku::Auth.password}"
    req['Range'] = "id ..; order=desc,max=1;"

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    response_json = res.body
    if response_json.bytes[0..1] == [31, 139] # gzip magic bytes
      io = StringIO.new(response_json, "rb")
      response_json = Zlib::GzipReader.new(io).read
    end
    response_data = JSON.parse(response_json)
  end

end
