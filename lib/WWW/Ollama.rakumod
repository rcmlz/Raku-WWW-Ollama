use v6.d;

unit module WWW::Ollama;

use WWW::Ollama::Client;
use JSON::Fast;

#| Access to Ollama client 
proto sub ollama-client(
        $input,
        Str:D :kind(:$path) = 'chat',   #= Path, one of 'completion', 'chat', 'embedding', 'model-info', 'list-models', or 'list-running-models'.
        :m(:$model) = Whatever,         #= Model to use, a string or Whatever.
        :f(:$format) = Whatever,        #= Format of the result; one of "json", "hash", "values", or Whatever.
        :$client = Whatever,            #= A WWW::Ollama::Client object or Whatever.
         ) is export {*}

multi sub ollama-client(
        $input,
        Str:D :kind(:$path) is copy = 'chat',
        :m(:$model) is copy = Whatever,
        :f(:$format) is copy = Whatever,
        :$client is copy = Whatever,
        *%args
                        ) {
    # Process model
    if $model.isa(Whatever) { $model = $path.lc ∈ <embed embedding embeddings> ?? 'nomic-embed-text' !! 'gemma3:1b' }
    die 'The argument $model is expected to be a string or Whatever.'
    unless $model ~~ Str:D;

    # Process format
    if $format.isa(Whatever) { $format = 'values' }
    die 'The argument $format is expected to be a string or Whatever.'
    unless $format ~~ Str:D;

    # Process client
    if $client.isa(Whatever) { $client = WWW::Ollama::Client.new }
    die 'The argument $client is expected to be a WWW::Ollama::Client object or Whatever.'
    unless $client ~~ WWW::Ollama::Client:D;

    # Delegate request
    my $ans;
    given $path.lc {
        when $_ ∈ <list-models models> {
            $ans = $client.list-models
        }
        when $_ ∈ <model-info> {
            $ans = $client.model-info(:$model)
        }
        when $_ ∈ <completion generation> {
            my %body = :$model, prompt => $input, :!stream, |%args;
            $ans = $client.completion(%body);
        }
        when $_ ∈ <embed embedding embeddings> {
            my %body = :$model, :$input, |%args;
            $ans = $client.embedding(%body);
        }
        when $_ ∈ <chat chat-completion> {
            my @messages = do given $input {
                when $_ ~~ Pair:D  { [%(role => $_.key, content => $_.value),] }
                when $_ ~~ (Array:D | List:D | Seq:D) {
                    if $_.all ~~ Map:D { $input }
                    elsif $_.all ~~ Pair:D { $_.map({ %(role => $_.key, content => $_.value) }).Array }
                    else { [%(role => "user", content => $_.join("\n")), ] }
                }
                when $_ ~~ Map:D { [$input, ] }
                when $_ ~~ Str:D { [%(role => "user", content => $_),] }
                default {
                    die 'Do not know how to process the input argument.'
                }
            }

            my %body = :$model, :@messages, |%args;
            $ans = $client.chat(%body)
        }
        default {
            die 'Do not know how to process the value of the $path argument.'
        }
    }

    # Result
    return do given $format.lc {
        when $_ ∈ <hash raku> { $ans }
        when $_ eq 'values' && $path ∉ <list-models models> {
            $path ~~ /embed/ ?? $ans<embeddings> !! $ans<content>
        }
        when $_ eq 'json' { to-json($ans, :pretty) }
        default { $ans }
    }
}

sub ollama-list-models(:$format = Whatever, :$client = Whatever) is export {
    return ollama-client('', path => 'list-models', :$format, :$client);
}

sub ollama-model-info(:$model = Whatever, :$format = Whatever, :$client = Whatever) is export {
    return ollama-client('', path => 'model-info', :$model, :$format, :$client);
}

sub ollama-completion($input, :$model = Whatever, :$format = Whatever, :$client = Whatever, *%args) is export {
    return ollama-client($input, path => 'completion', :$model, :$format, :$client, |%args);
}

sub ollama-chat-completion($input, :$model = Whatever, :$format = Whatever, :$client = Whatever, *%args) is export {
    return ollama-client($input, path => 'chat', :$model, :$format, :$client, |%args);
}