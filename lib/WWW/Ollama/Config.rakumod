use v6.d;

use JSON::Fast;

# Persistent configuration for defaults and user preferences.
class WWW::Ollama::Config {
    has IO::Path $.path;
    has %.data is rw;

    submethod BUILD(:$!path = self.default-path()) {
        %!data = self.default-config();
        self.load();
    }

    method default-path() {
        my $home = $*HOME // IO::Path.new('.');
        return $home.add('.raku').add('ollama-client.json');
    }

    method default-config() {
        return {
            host               => '127.0.0.1',
            port               => 11434,
            use-system-ollama  => True,
            start-ollama       => True,
            context-length     => Nil,
            echo               => False,
        };
    }

    method load() {
        if $.path.e {
            try {
                %!data = from-json($.path.slurp);
            }
            CATCH {
                %!data = self.default-config();
            }
        }
    }

    method save() {
        $.path.parent.mkdir unless $.path.parent.d;
        $.path.spurt(to-json(%!data, :pretty));
    }

    method get($key, $default = Nil) {
        return %!data{$key} // $default;
    }

    method set(%updates) {
        for %updates.kv -> $k, $v {
            %!data{$k} = $v;
        }
        self.save();
    }
}
