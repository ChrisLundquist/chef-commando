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

