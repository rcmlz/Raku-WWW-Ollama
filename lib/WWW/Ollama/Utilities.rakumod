use v6.d;

unit module WWW::Ollama::Utilities;

use paths;

# Locate an executable on PATH (with simple platform awareness).
our sub find-in-path(Str:D $name) {
    return IO::Path.new($name) if IO::Path.new($name).e && IO::Path.new($name).f;
    # What is the Windows separator?
    my $sep = ':';
    for (%*ENV<PATH> // '').split($sep) -> $dir {
        my $candidate = IO::Path.new($dir).add($name);
        return $candidate if $candidate.e && $candidate.f;
        if $*DISTRO.is-win {
            for <.exe .bat .cmd> -> $ext {
                my $win = IO::Path.new($dir).add($name ~ $ext);
                return $win if $win.e && $win.f;
            }
        }
    }
    Nil;
}


# Helpers
our sub encode-image($item) {
    my $path = $item ~~ IO::Path ?? $item !! IO::Path.new($item) if $item ~~ Str && IO::Path.new($item).e;
    my $data;
    my $format = 'jpeg';
    if $path && $path.e {
        $data = $path.slurp(:bin);
        $format = $path.extension // 'jpeg';
    } elsif $item ~~ Buf {
        $data = $item;
    } elsif $item ~~ Str && $item.starts-with('http') {
        my $buf = fetch-url($item);
        $data = $buf if $buf;
        $format = IO::Path.new($item).extension // $format;
    } elsif $item.defined {
        $data = $item.Str.encode;
    }
    return Nil unless $data;
    "data:image/{$format};base64," ~ MIME::Base64.encode-str($data, :oneline);
}

our sub fetch-url(Str $url) {
    my $curl = find-in-path($*DISTRO.is-win ?? 'curl.exe' !! 'curl') or return Nil;
    my $proc = run $curl.Str, '-sS', $url, :out, :err, :bin;
    my $out  = $proc.out.slurp-rest;
    return Nil if $proc.exitcode // 1;
    $out;
}

our sub deterministic-id(Str $str) {
    my $hash = 5381;
    for $str.comb -> $c {
        $hash = (($hash +< 5) + $hash) + $c.ord;
    }
    "tool-" ~ $hash.abs.base(36);
}

our sub to-seconds(%data) {
    {
        total       => (%data<total_duration> // 0) / 1_000_000_000,
        load        => (%data<load_duration> // 0) / 1_000_000_000,
        prompt_eval => (%data<prompt_eval_duration> // 0) / 1_000_000_000,
        eval        => (%data<eval_duration> // 0) / 1_000_000_000,
    }
}

our sub throughput(%data) {
    my $tokens = (%data<eval_count> // 0) + (%data<prompt_eval_count> // 0);
    my $duration = (%data<total_duration> // 1) / 1_000_000_000;
    $duration > 0 ?? $tokens / $duration !! 0;
}

