use v6.d;

use JSON::Fast;
use HTTP::Tiny;
use WWW::Ollama::Utilities;

# Thin HTTP helper; supports JSON requests and streaming via curl for simplicity.
class WWW::Ollama::HTTPClient {
    has $.scheme is rw = Whatever;
    has $.host is rw = Whatever;
    has $.port is rw = Whatever;
    has $.api-key is rw = Whatever;

    #------------------------------------------------------
    # Creators
    #------------------------------------------------------
    submethod BUILD(:$!host = Whatever, :$!port = Whatever, :$!scheme = Whatever, :$!api-key = Whatever) {
        without $!host { $!host = '127.0.0.1' }
        die "The host spec is expected to be a string or Whatever" unless $!host ~~ Str:D;
        say (:$!scheme, :$!host, :$!port);
        without $!port {
            $!port = do given $!host {
                $!port = do when $_ ~~ /^ 'https://' / {
                    $!scheme = 'https';
                    443
                }
                when $_ ~~ /^ 'http://' / {
                    $!scheme = 'http';
                    80
                }
                default {
                    11434
                }
            }
        }
        say (:$!scheme, :$!host, :$!port);
        $!scheme //= 'http';
        $!host .= subst( $!scheme ~ '://');
        say (:$!scheme, :$!host, :$!port);
    }

    #------------------------------------------------------
    # API methods
    #------------------------------------------------------
    method base-url() {
        "{$!scheme}://{$!host}:{$!port}"
    }

    method get(Str:D $path, :%headers = {}) {
        my $response = HTTP::Tiny.new.get(self.base-url ~ $path);
        # Does headers .get take headers argument?
        # %headers<Authorization> = "Bearer $!api-key" with $!api-key;
        my %res = $response;
        if $response<success> {
            my $json-string = $response<content>.decode;
            try {
                $json-string = from-json($json-string);
            }
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
        %headers<Authorization> = "Bearer $!api-key" with $!api-key;
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
        %headers<Authorization> = "Bearer $!api-key" with $!api-key;
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
}
