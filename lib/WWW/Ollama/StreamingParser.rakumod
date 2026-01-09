use v6.d;

# Parse streaming chunks from Ollama into structured hashes.
class WWW::Ollama::StreamingParser {
    method parse(Supply $lines, Str $call-id) {
        supply {
            whenever $lines -> $line {
                my $chunk = self.parse-line($line, $call-id);
                emit $chunk if $chunk.defined;
            }
        }
    }

    method parse-line(Str $line, Str $call-id) {
        my %res = try { from-json($line) } // {};
        if %res {
            if %res<error> {
                return { :event('error'), :call-id($call-id), :payload(%res) };
            }
            my %chunk = (
            event   => 'chunk',
            call-id => $call-id,
            model   => %res<model>,
            role    => %res<message><role> // %res<role>,
            content => (%res<message><content> // %res<response> // %res<content> // ''),
            finish  => %res<done> // False,
            usage   => %res<eval_count> ?? { completion => %res<eval_count>, prompt => %res<prompt_eval_count> } !! Nil,
            tool-calls => %res<message><tool_calls>,
            reasoning => %res<thinking>,
            );
            return %chunk;
        }
        if $line.trim.chars {
            return { :event('text'), :call-id($call-id), :payload($line) };
        }
        Nil;
    }
}