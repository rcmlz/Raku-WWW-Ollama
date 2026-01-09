use v6.d;

use WWW::Ollama::HTTPClient;

# Map friendly inputs to Ollama API payloads.
class WWW::Ollama::RequestNormalizer {
    has WWW::Ollama::HTTPClient $.http;

    method normalize(Str $kind, %params is copy) {
        my %payload = %params;

        my %map =
            Model           => 'model',
            Name            => 'name',
            Messages        => 'messages',
            Prompt          => 'prompt',
            Input           => 'input',
            Stream          => 'stream',
            Tools           => 'tools',
            ResponseFormat  => 'format',
            response-format => 'format',
            KeepAlive       => 'keep_alive',
            keep-alive      => 'keep_alive',
            Images          => 'images',
            Modelfile       => 'modelfile',
            Path            => 'path',
            Reasoning       => 'think',
            Suffix          => 'suffix',
        ;

        for %map.kv -> $friendly, $api {
            if %payload{$friendly}:exists {
                %payload{$api} = %payload{$friendly};
                %payload{$friendly}:delete;
            }
        }

        given $kind {
            when 'chat' | 'completion' {
                %payload<model> //= 'qwen2.5:7b';
                %payload<stream> //= False;
            }
            when 'embedding' {
                %payload<model> //= 'nomic-embed-text';
            }
        }

        %payload<options> //= {};
        my %option-map =
            ContextLength           => 'num_ctx',
            context-length          => 'num_ctx',
            Temperature             => 'temperature',
            temperature             => 'temperature',
            MaxTokens               => 'num_predict',
            max-tokens              => 'num_predict',
            StopTokens              => 'stop',
            stop-tokens             => 'stop',
            TotalProbabilityCutoff     => 'top_p',
            total-probability-cutoff   => 'top_p',
            MinimumProbabilityCutoff   => 'min_p',
            minimum-probability-cutoff => 'min_p',
            FrequencyPenalty        => 'repeat_penalty',
            frequency-penalty       => 'repeat_penalty',
            RandomSeed              => 'seed',
            random-seed             => 'seed',
        ;

        for %option-map.kv -> $friendly, $api {
            if %payload{$friendly}:exists {
                my $val = %payload{$friendly};
                %payload{$friendly}:delete;
                next if $val === Nil;
                %payload<options>{$api} = $val eq 'Automatic'
                        ?? self.model-context-length(%payload<model>)
                        !! $val;
            }
        }
        %payload<options>:delete unless %payload<options>.keys;

        if $kind eq 'chat' {
            %payload<messages> = self.preprocess-messages(%payload<messages> // []);
        }
        if %payload<images>:exists {
            %payload<images> = self.preprocess-images(%payload<images>);
        }
        if %payload<tools>:exists {
            %payload<tools> = self.normalize-tools(%payload<tools>);
        }

        %payload<server> = $.http.base-url;
        %payload;
    }

    method preprocess-messages(@messages) {
        my @out;
        for @messages -> $msg {
            my %m = $msg ~~ Hash ?? $msg.clone !! $msg.Hash;
            my $role = (%m<role> // %m<Role> // 'user').lc;
            my $content = %m<content> // %m<Content> // '';
            my @images = self.preprocess-images(%m<images> // %m<Images> // []);
            my %out = role => $role;
            my $text = $content ~~ Array ?? $content.join(' ') !! $content.Str;
            %out<content> = $text if $text.chars;
            %out<images>  = @images if @images.elems;
            %out<tool_calls> = self.preprocess-tool-requests(%m<ToolRequests> // []) if %m<ToolRequests>;
            @out.push(%out);
            if %m<ToolResponses> {
                for %m<ToolResponses> -> $resp {
                    my %r = $resp ~~ Hash ?? $resp !! $resp.Hash;
                    my $id = %r<tool_call_id> // WWW::Ollama::Utilities::deterministic-id(%r<name> // 'tool' ~ %r<content>);
                    @out.push({
                        role         => 'tool',
                        tool_call_id => $id,
                        content      => (%r<content> // '').Str,
                    });
                }
            }
        }
        @out;
    }

    method preprocess-images($images) {
        my @imgs = $images ~~ Array ?? $images !! [$images];
        @imgs.map({
            if $_ ~~ Hash {
                my %h = $_;
                my $detail = %h<detail> // %h<Detail>;
                my $source = %h<data> // %h<image> // %h<path> // %h<url> // %h<file> // '';
                my $encoded = WWW::Ollama::Utilities::encode-image($source);
                return Nil unless $encoded;
                return $detail ?? { data => $encoded, detail => $detail.lc } !! $encoded;
            }
            WWW::Ollama::Utilities::encode-image($_);
        }).grep(*.defined);
    }

    method preprocess-tool-requests($reqs) {
        my @requests = $reqs ~~ Array ?? $reqs !! [$reqs];
        @requests.map({
            my %r = $_ ~~ Hash ?? $_ !! $_.Hash;
            my $name = %r<name> // %r<Name> // 'function';
            my $args = %r<arguments> // %r<Arguments> // {};
            my $id   = %r<id> // WWW::Ollama::Utilities::deterministic-id($name ~ to-json($args, :!pretty));
            {
                id   => $id,
                type => 'function',
                function => {
                    name      => $name,
                    arguments => $args ~~ Str ?? $args !! to-json($args, :!pretty),
                }
            }
        });
    }

    method normalize-tools($tools) {
        my @tools = $tools ~~ Array ?? $tools !! [$tools];
        @tools.map({
            my %t = $_ ~~ Hash ?? $_ !! $_.Hash;
            {
                type => 'function',
                function => {
                    name        => %t<name> // %t<Name> // '',
                    description => %t<description> // %t<Description>,
                    parameters  => %t<parameters> // %t<Parameters> // {},
                }
            }
        });
    }

    method model-context-length($model) {
        my %defaults = (
        'qwen2.5:7b'        => 8192,
        'nomic-embed-text'  => 8192,
        );
        %defaults{$model} // 8192;
    }
}
