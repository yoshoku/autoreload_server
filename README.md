# autoreload_web_server

A simple web server for local development that provides an auto-reloading feature. It automatically refreshes the browser when a file is changed.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add autoreload_web_server
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install autoreload_web_sever
```

## Usage

Start autoreload-server:

```sh
$ ls -1 public/
index.html
$ autoreload-web-server public
```

Then, access to http://localhost:4000/.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/yoshoku/autoreload_web_server.
This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/yoshoku/autoreload_web_server/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the AutoreloadWebServer project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/yoshoku/autoreload_web_server/blob/main/CODE_OF_CONDUCT.md).
