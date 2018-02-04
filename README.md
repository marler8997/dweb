## Requirements

* bidmake (https://github.com/marler8997/bidmake)
```
bb -version
```

This tool uses the "mored" library found at https://github.com/marler8997/mored 
It will be downloaded automatically by "bidmake" during a build.

## TODO

#### Create an HTTP virtual host forward server
  This can be used to forward requests to different endpoints based on the HTTP host.
  This would be useful for something sharing dweb with other http servers.  Based on
  the HTTP host, dweb could handle requests directly or forward them to other HTTP servers.
#### Allow server to be configured via ESB, i.e.
```
httpserver 80
{
    virtualhost "*.something.com"
    {
        root "/var/www/something.com"
    }
}
```