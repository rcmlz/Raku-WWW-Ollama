use v6.d;

use JSON::Fast;
use HTTP::Tiny;
use WWW::Ollama::Utilities;

# Thin HTTP helper; supports JSON requests and streaming via curl for simplicity.
class WWW::Ollama::HTTPClient {
    has Str $.host is rw;
    has Int $.port is rw;
    has IO::Path $.curl-path is rw = WWW::Ollama::Utilities::find-in-path($*DISTRO.is-win ?? 'curl.exe' !! 'curl');

    method host-port() { "$!host:$!port" }
    method base-url()  { "http://{self.host-port}" }

    method !request-curl(Str $method, Str $path, %options = {}) {
        my %opts = %options;
        %opts<headers> //= {};
        my $curl = $.curl-path // WWW::Ollama::Utilities::find-in-path($*DISTRO.is-win ?? 'curl.exe' !! 'curl');
        return { status => 599, reason => 'curl not found', content => '' } unless $curl;
        my @cmd = $curl.Str, '-sS', '-w', '"\n%{http_code}"', '-X', $method, self.base-url ~ $path;
        for %opts<headers>.kv -> $k, $v {
            @cmd.push('-H', "$k: $v");
        }
        if %opts<content> {
            @cmd.push('-d', %opts<content>);
        }
        my $proc = run |@cmd, :out, :err, :bin;
        my $out = $proc.out.slurp.decode;
        my $err = $proc.err.slurp.decode;
        my @lines = $out.lines;
        my $status = @lines.pop // 0;
        my $content = @lines.join("\n");
        my %res = (
        status  => $status.Int,
        reason  => $err,
        content => $content,
        );
        %res<decoded-content> = try { from-json($content) } if $content.chars;
        %res;
    }

    method !request(Str $method, Str $path, %options = {}) {

    }

    #------------------------------------------------------
    # API methods
    #------------------------------------------------------
    method get(Str:D $path, :%headers = {}) {
        my $response = HTTP::Tiny.new.get(self.base-url ~ $path);
        my %res = $response;
        if $response<success> {
            my $json-string = $response<content>.decode;
            $json-string = try from-json($json-string);
            if $! { $json-string = {'response' => $json-string} }
            %res<decoded-content> = $json-string;
        } else {
            try {
                %res<decoded-content> = $response<content>.decode;
            }
        }
        return %res;
    }

    method delete(Str $path, %data? is copy, :%headers = {}) {
        %headers<Content-Type> //= 'application/json';
        my $response = HTTP::Tiny.delete(self.base-url ~ $path, :%headers, content => to-json(%data, :!pretty));
        my %res = $response;
        if $response<success> {
            my $json-string = $response<content>.decode;
            %res<decoded-content> = $json-string;
        }
        return %res;
    }

    method post(Str $path, %data, :%headers = {}) {
        %headers<Content-Type> //= 'application/json';
        my $response = HTTP::Tiny.post(self.base-url ~ $path, :%headers, content => to-json(%data, :!pretty));
        my %res = $response;
        if $response<success> {
            my $json-string = $response<content>.decode;
            $json-string = try from-json($json-string);
            if $! { $json-string = {'response' => $json-string} }
            %res<decoded-content> = $json-string;
        }
        return %res;
    }

    method post-stream(Str $path, %data, :$call-id) {
        my $json = to-json(%data, :!pretty);
        my $url  = self.base-url ~ $path;
        my $curl = $*DISTRO.is-win ?? 'curl.exe' !! 'curl';
        my $curl-path = WWW::Ollama::Utilities::find-in-path($curl);
        unless $curl-path {
            return Supply.once({:event('error'), :call-id($call-id), :message("curl not available for streaming")});
        }
        my $proc = Proc::Async.new($curl-path.Str, '-sN', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', $json, $url);
        my $started = $proc.start;
        supply {
            whenever $proc.stdout.lines -> $line {
                emit $line;
            }
            whenever $proc.stderr.lines -> $err {
                emit $err if $err.chars;
            }
            whenever $started {
                QUIT { }
            }
        }
    }

    #------------------------------------------------------
    # Methods based on HTTP::Tiny
    #------------------------------------------------------
    method tiny-delete(Str :$url!,
                    Str :api-key(:$auth-key)!,
                    Bool :$decode = True,
                    UInt :$timeout = 10) {

        my $resp = HTTP::Tiny.delete: $url,
                headers => { authorization => "Bearer $auth-key",
                             Content-Type => "application/json" };

        return $decode ?? $resp<content>.decode !! $resp<content>;
    }

    multi method tiny-post(Str :$url!,
                        Str :$body!,
                        Str :api-key(:$auth-key)!,
                        Str :$output-file = '',
                        Bool :$decode = True,
                        UInt :$timeout = 10) {

        my $resp = HTTP::Tiny.post: $url,
                headers => { authorization => "Bearer $auth-key",
                             Content-Type => "application/json" },
                content => $body;

        if $output-file {
            spurt($output-file, $resp<content>);
        }
        return $decode ?? $resp<content>.decode !! $resp<content>;
    }

    multi method tiny-post(Str :$url!,
                        :$body! where *~~ Map,
                        Str :api-key(:$auth-key)!,
                        Bool :$json = False,
                        Str :$output-file = '',
                        Bool :$decode = True,
                        UInt :$timeout = 10) {
        if $json {
            return self.tiny-post(:$url, body => to-json($body), :$auth-key, :$output-file, :$timeout);
        }

        my $resp = HTTP::Tiny.post: $url,
                headers => { authorization => "Bearer $auth-key" },
                content => $body;

        if $output-file {
            spurt($output-file, $resp<content>);
        }
        return $decode ?? $resp<content>.decode !! $resp<content>;
    }
}
