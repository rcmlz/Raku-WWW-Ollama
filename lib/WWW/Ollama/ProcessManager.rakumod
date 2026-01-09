use v6.d;

use WWW::Ollama::HTTPClient;
use WWW::Ollama::ExecResolver;

# Manage the ollama process lifecycle.
class WWW::Ollama::ProcessManager {
    has WWW::Ollama::ExecResolver $.resolver;
    has WWW::Ollama::HTTPClient $.http;
    has Bool $.start-on-missing is rw = True;
    has $.context-length is rw;
    has Proc::Async $!proc;

    multi method host() { $!http.host }
    multi method host(Str $host) { $!http.host = $host; }
    multi method port() { $!http.port }
    multi method port(Int $port) { $!http.port = $port; }
    method base() { $!http.host ~ ':' ~ $!http.port }

    method is-running() {
        try {
            my %res = $.http.get('/api/ps');
            return %res<status> && %res<status> == 200;
        }
        #if $! { return False }
        return False;
    }

    method ensure-running(:$use-system) {
        return True if self.is-running();
        return Failure.new(:message("Ollama not running and auto-start disabled")) unless $!start-on-missing;
        self.start(:$use-system);
    }

    method start(:$use-system) {
        return True if $!proc && $!proc.started;
        my $exec = $.resolver.resolve(:prefer-system($use-system));
        return Failure.new(:message("Could not resolve ollama executable")) unless $exec;
        my %env = %*ENV.clone;
        %env<OLLAMA_HOST> = self.base;
        %env<OLLAMA_CONTEXT_LENGTH> = $!context-length with $!context-length;
        $!proc = Proc::Async.new($exec.Str, 'serve', :%env);
        $!proc.stdout.tap({ note "[ollama] $_" if $_.chars });
        $!proc.stderr.tap({ note "[ollama] $_" if $_.chars });
        $!proc.start;
        my $waited = 0;
        while $waited < 30 {
            sleep 0.2;
            $waited += 0.2;
            last if self.is-running();
        }
        return self.is-running() ?? True !! Failure.new(:message("Failed to start ollama on {self.base}"));
    }

    method stop() {
        if $!proc {
            $!proc.terminate;
            await $!proc.closed;
            $!proc = Nil;
        }
        True;
    }
}
