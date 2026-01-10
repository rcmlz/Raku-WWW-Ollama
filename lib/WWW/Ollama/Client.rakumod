
use JSON::Fast;
use MIME::Base64;
use WWW::Ollama::Config;
use WWW::Ollama::HTTPClient;
use WWW::Ollama::ExecResolver;
use WWW::Ollama::RequestNormalizer;
use WWW::Ollama::StreamingParser;
use WWW::Ollama::ProcessManager;

# Public client facade.
class WWW::Ollama::Client {
    has WWW::Ollama::Config $.config;
    has WWW::Ollama::HTTPClient $.http;
    has WWW::Ollama::ExecResolver $.resolver;
    has WWW::Ollama::RequestNormalizer $.normalizer;
    has WWW::Ollama::StreamingParser $.parser .= new;
    has WWW::Ollama::ProcessManager $.process handles <start stop>;

    submethod BUILD(:$host, :$port, :$use-system-ollama, :$start-ollama, Bool:D :$echo = False) {
        $!config //= WWW::Ollama::Config.new;
        $!config.set({'host' => $host}) if $host;
        $!config.set({'port' => $port}) if $port.defined;
        $!config.set({'use-system-ollama' => $use-system-ollama}) if $use-system-ollama.defined;
        $!config.set({'start-ollama' => $start-ollama}) if $start-ollama.defined;
        $!config.set({:$echo});

        $!http //= WWW::Ollama::HTTPClient.new(
            host => $!config.get('host', '127.0.0.1'),
            port => $!config.get('port', 11435),
        );

        $!resolver //= WWW::Ollama::ExecResolver.new(:$!config);
        $!normalizer //= WWW::Ollama::RequestNormalizer.new(:$!http);
        $!process //= WWW::Ollama::ProcessManager.new(
            :$!resolver,
            :$!http,
            start-on-missing => $!config.get('start-ollama', True),
            context-length   => $!config.get('context-length'),
            :$echo
        );
    }

    multi method host() { $!http.host }
    multi method host(Str $value) {
        $!http.host = $value;
        $!config.set(host => $value);
    }

    multi method port() { $!http.port }
    multi method port(Int $value) {
        $!http.port = $value;
        $!config.set(port => $value);
    }

    multi method use-system-ollama() { $!resolver.use-system }
    multi method use-system-ollama(Bool $value) { $!config.set('use-system-ollama' => $value) }

    method ollama-is-running() { $!process.is-running }
    method ensure-ollama-running(:$use-system) { $!process.ensure-running(:$use-system) }

    # API wrappers
    method status(:$ensure-running = True) {
        self.ensure-ollama-running if $ensure-running;
        my %res = $!http.get('');
        return %res<decoded-content> // %res<status> // "Can't process http request.";
    }

    #| List models that are currently loaded into memory.
    method list-running-models(:$ensure-running = True) {
        self.ensure-ollama-running if $ensure-running;
        my %res = $!http.get('/api/ps');
        self.shape-response('models', %res);
    }

    #| List models that are available locally.
    method list-models(:$ensure-running = True) {
        self.ensure-ollama-running if $ensure-running;
        my %res = $!http.get('/api/tags');
        self.shape-response('models', %res);
    }

    #| Show information about a model including details, modelfile, template, parameters, license, system prompt.
    method model-info(Str :$model!, :$verbose = False, :$ensure-running = True) {
        self.ensure-ollama-running if $ensure-running;
        my %res = $!http.post('/api/show', { model => $model, verbose => $verbose });
        self.shape-response('model-info', %res);
    }

    #| Download a model from the ollama library.
    method pull-model(Str :$model!, :$stream = False, :$ensure-running = True) {
        self.ensure-ollama-running if $ensure-running;
        my %payload = :$model, :$stream;
        if $stream {
            my $call = self.call-id('pull');
            return $!parser.parse($!http.post-stream('/api/pull', %payload, :call-id($call)), $call);
        }
        my %res = $!http.post('/api/pull', %payload);
        self.shape-response('pull', %res);
    }

    #| Delete a model and its data.
    method delete-model(Str :$model!, :$ensure-running = True) {
        self.ensure-ollama-running if $ensure-running;
        my %res = $!http.delete('/api/delete', { model => $model });
        self.shape-response('delete', %res);
    }

    #| Create a model from: another model, a safetensors directory, or a GGUF file.
    method create-model(:$name!, :$modelfile!, :$path?, :$stream = False, :$ensure-running = True) {
        self.ensure-ollama-running if $ensure-running;
        my %payload = :$name, :$modelfile, :$path, :$stream;
        my $call = self.call-id('create');
        if $stream {
            return $!parser.parse($!http.post-stream('/api/create', %payload, :call-id($call)), $call);
        }
        self.shape-response('create', $!http.post('/api/create', %payload));
    }

    #| Check if a blob exists.
    method blob-exists(Str :$digest!, :$ensure-running = True) {
        self.ensure-ollama-running if $ensure-running;
        my %res = $!http.get("/api/blobs/sha256:$digest");
        %res<status> && %res<status> == 200;
    }

    #| Create a blob exists.
    method create-blob(Str :$digest!, :$content!, :$ensure-running = True) {
        self.ensure-ollama-running if $ensure-running;
        my %res = $!http.post("/api/blobs/sha256:$digest", { content => $content });
        self.shape-response('blob', %res);
    }

    #| Retrieve the Ollama version.
    method version(:$ensure-running = True) {
        self.ensure-ollama-running if $ensure-running;
        my %res = $!http.get('/api/version');
        self.shape-response('version', %res);
    }

    #| Generate a completion.
    multi method completion(Str:D $prompt, :$ensure-running = True) {
        my %body = model => 'gemma3:1b', :$prompt, :!stream;
        return self.completion(%body, :$ensure-running);
    }

    #| Generate a completion response for a given prompt with a provided model.
    multi method completion(%params is copy, :$ensure-running = True) {
        self.ensure-ollama-running if $ensure-running;
        my %payload = $!normalizer.normalize('completion', %params);
        my $stream = %payload<stream> // False;
        my $call   = self.call-id('completion');
        return self!do-chat-or-completion('/api/generate', %payload, $stream, $call);
    }

    #| Generate the next message in a chat with a provided model.
    method chat(%params is copy, :$ensure-running = True) {
        self.ensure-ollama-running if $ensure-running;
        my %payload = $!normalizer.normalize('chat', %params);
        my $stream = %payload<stream> // False;
        my $call   = self.call-id('chat');
        return self!do-chat-or-completion('/api/chat', %payload, $stream, $call);
    }

    #| Generate embeddings from a model.
    method embedding(%params is copy, :$ensure-running = True) {
        self.ensure-ollama-running if $ensure-running;
        my %payload = $!normalizer.normalize('embedding', %params);
        %payload<input> //= %payload<text> if %payload<text>;
        my $res = $!http.post('/api/embed', %payload);
        if self!needs-model(%payload<model>, $res) {
            self.pull-model(model => %payload<model>, :ensure-running);
            $res = $!http.post('/api/embed', %payload);
        }
        self.shape-response('embedding', $res);
    }

    method models-local(:$ensure-running = True) {
        self.list-models(:$ensure-running);
    }

    method models-chat() { <gemma3:1b llama3 qwen2.5:7b> } # stubbed helper
    method models-embedding() { <nomic-embed-text all-minilm> }
    method models-remote(:$type = 'all') { ["remote-$type list not implemented"] }

    # Internal helpers
    method !do-chat-or-completion(Str $path, %payload, Bool $stream, Str $call) {
        if $stream {
            return $!parser.parse($!http.post-stream($path, %payload, :call-id($call)), $call);
        }
        my %res = $!http.post($path, %payload);
        if self!needs-model(%payload<model>, %res) {
            self.pull-model(model => %payload<model>, :ensure-running);
            %res = $!http.post($path, %payload);
        }
        self.shape-response('chat', %res);
    }

    method !needs-model($model, %res) {
        my %decoded = %res<decoded-content> // {};
        my $err = (%decoded<error> // '').lc;
        (%res<status> && %res<status> == 404)
            || $err.contains('not found')
            || $err.contains('pull');
    }

    method shape-response(Str $kind, %res) {
        return { error => %res<reason> // 'unknown error', status => %res<status> // 500 } unless %res<status> && %res<status> ~~ 200..299;
        my %data = %res<decoded-content> // {};
        given $kind {
            when 'chat' | 'completion' {
                my $content = %data<message><content> // %data<response> // '';
                my $reasoning = %data<thinking> // %data<message><reasoning>;
                my $shaped-content = $reasoning.defined ?? [ { reasoning => $reasoning }, { text => $content } ] !! $content;
                my %result =
                    role          => %data<message><role> // 'assistant',
                    content       => $shaped-content,
                    tool-requests => %data<message><tool_calls>,
                    model         => %data<model>,
                    timestamp     => DateTime.now,
                    finish-reason => %data<done_reason>,
                    usage         => {
                        prompt     => %data<prompt_eval_count> // 0,
                        completion => %data<eval_count> // 0,
                    },
                    durations     => WWW::Ollama::Utilities::to-seconds(%data),
                    throughput    => WWW::Ollama::Utilities::throughput(%data),
                ;
                %result<context> = %data<context> unless %result<role>.defined;
                return %result;
            }
            when 'embedding' {
                return {
                    embeddings => %data<embeddings> // [],
                    model      => %data<model>,
                    timestamp  => DateTime.now,
                    usage      => { prompt => %data<prompt_eval_count> // 0 },
                };
            }
            when 'models' { return %data<models> // [] }
            default       { return %data }
        }
    }

    method call-id($prefix) { "$prefix-" ~ DateTime.now.posix ~ "-" ~ (1000 + (rand * 100000).Int) }

    #------------------------------------------------------
    # Representation
    #------------------------------------------------------
    #| To Hash
    multi method Hash(::?CLASS:D:-->Hash) {
        return
                {
                    :$!config,
                    :$!http,
                    :$!resolver,
                    :$!normalizer,
                    :$!parser,
                    :$!process,
                };
    }

    #| To string
    multi method Str(::?CLASS:D:-->Str) {
        return self.gist;
    }

    #| To gist
    multi method gist(::?CLASS:D:-->Str) {
        my @spec =
                base-url => $!http.base-url,
                ollama-is-running => self.ollama-is-running,
                |self.version,
                models-in-memory => self.list-running-models.elems,
                local-models => self.list-models.elems;
                #status => self.status<response>;
        return 'Ollama::Client' ~ @spec.List.raku;
    }
}
