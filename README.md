##
I wrote this for Test-Kitchen 1.0

It is an abomination of chef-apply and chef-solo.
Basically, think of chef-apply given a certain context.

It lets me do things like this.

```bash
sudo ./bin/chef-commando  -j ./node.json -e "puts node.redis.inspect"
{"version"=>"2.4.8", "dir"=>"/usr/local/redis", "dirs"=>["bin", "etc", "log", "run"], "binaries"=>["redis-benchmark", "redis-cli", "redis-server", "redis-check-aof", "redis-check-dump"], "daemonize"=>"yes", "pidfile"=>"/usr/local/redis/run/redis.pid", "port"=>"6379", "bind"=>"0.0.0.0", "timeout"=>"300", "loglevel"=>"notice", "logfile"=>"/usr/local/redis/log/redis.log", "databases"=>"16", "appendonly"=>"no", "appendfsync"=>"everysec", "no_appendfsync_on_rewrite"=>"no", "vm_enabled"=>"no", "vm_swap_file"=>"/tmp/redis.swap", "vm_max_memory"=>"0", "vm_page_size"=>"32", "vm_pages"=>"134217728", "vm_max_threads"=>"4", "glueoutputbuf"=>"yes", "hash_max_zipmap_entries"=>"64", "hash_max_zipmap_value"=>"512", "activerehashing"=>"yes"}
```

This way I can dump and load a node context so I can run templates in that context
without modifying the run list that we are testing.

That means when you have a prepare_recipe.rb like this

```ruby
Dir["/opt/kb/suites/bats/**/*.erb"].each do |bats_template|
  bats_name = bats_template.split(".erb").first

  template bats_name do
    source bats_template
  end
end
```

then you can use node attributes in a template for a test like this

```erb
#!/usr/bin/env bats

@test "the log dir (<%= node.example.log_dir %>) should be owned by our user (<%= node.example.user %>)" {
  [ "$(stat -c %U <%= node.example.log_dir %>| grep <%= node.example.user %>)" ]
}

@test "should create the log dir (<%= node.example.log_dir %>)" {
  [ -d <%= node.example.log_dir %> ]
  }

@test "the configuration file should have the right password" {
  [ "$(grep '<%= node.example.password %>' /tmp/example.conf )" ]
}
```

That way, when the tests run, you get output like this


```
-----> Preparing bats suite with /opt/kb/suites/bats/prepare_recipe.rb
1..3
ok 1 the log dir (/tmp/var/log/example) should be owned by our user (example)
ok 2 should create the log dir (/tmp/var/log/example)
ok 3 the configuration file should have the right password
```

## Installation
Currently you have to install it manually, but I am working to get it a first class kb plugin.

Step 1) ( Please tell me a better way)
Install the plugin Inside the vagrant
```
vagrant@default-ubuntu-1204:~$ sudo /opt/kb/bin/kb install chef-commando:https://github.com/ChrisLundquist/chef-commando/archive/master.tar.gz
```

Step 2)
Make /opt/kb/libexec/kb-suite-prepare use chef-commando instead of chef-apply to get access to node recipe default attributes
```
#!/usr/bin/env bash
# Usage: kb suite-prepare <plugin>
set -e
[ -n "$KB_DEBUG" ] && set -x

banner()  { echo "-----> $*" ; }
info()    { echo "       $*" ; }
warn()    { echo ">>>>>> $*" >&2 ; }

plugin="$1"
prepare_script="$(kb-suitepath $plugin)/prepare.sh"
prepare_recipe="$(kb-suitepath $plugin)/prepare_recipe.rb"

if [ -x "$prepare_script" ] ; then
  banner "Preparing $plugin suite with $prepare_script"
  "$prepare_script"
fi

if [ -f "$prepare_recipe" ] ; then
  banner "Preparing $plugin suite with $prepare_recipe"
  kb chef-commando "$prepare_recipe" -c /tmp/vagrant-chef-1/solo.rb -j /tmp/vagrant-chef-1/dna.json
fi
```

Step 3)
Run `bundle exec kitchen verify`


## LICENSE
MIT

## Authors
2013 Chris Lundquist
