# Heroku surrogate

The `heroku surrogate` command pulls down the environment variables for a
Heroku application, merges them into the local environment, and spawns a
process.  Behold!

    heroku surrogate rake db:migrate:up VERSION=20130228193803

This runs the migration locally, but connected to the `DATABASE_URL` specified
by the server.  This is great for sneaking a nondestructive migration out
before the actual deploy, thus minimizing downtime.

The fun doesn't stop there.  You can pass in a process type from your
`Procfile` or any arbitrary command.  Spin up a console.  Spin up a worker.
Heck, spin up a web server if you want.

    heroku surrogate console
    heroku surrogate worker
    heroku surrogate PORT=3000 web

The `--release` option lets you use the environment and process types from an
earlier release.

    heroku surrogate --release=v123 env

Note that you're using development code against production resources.  If
you'd rather be running production code as well, pass `--checkout`, and the
appropriate commit (respecting `--release` if given) will be checked out
before executing.

    heroku surrogate --checkout --release=v456 $SHELL

## Installation

    $ heroku plugins:install https://github.com/tpope/heroku-surrogate.git
