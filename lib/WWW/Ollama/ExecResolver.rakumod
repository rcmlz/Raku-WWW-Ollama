use v6.d;

use WWW::Ollama::Config;
use WWW::Ollama::Utilities;

# Resolve the ollama executable from system or bundled resources.
class WWW::Ollama::ExecResolver {
    has WWW::Ollama::Config $.config;
    has IO::Path $.root;

    submethod BUILD(:$!config!, :$root) {
        $!root = $root // $?FILE.IO.dirname.IO; # repo root
    }

    method use-system() {
        $!config.get('use-system-ollama', True);
    }

    method find-exec(Str $name) {
        my $found = WWW::Ollama::Utilities::find-in-path($name);
        $found;
    }

    method system-path() {
        self.find-exec('ollama');
    }

    method bundled-path() {
        my $os   = $*KERNEL.name.lc;
        my $arch = ($*KERNEL.hardware // '').lc;
        my $dir  = do {
            if $os ~~ /win/        { 'Windows-x86-64' }
            elsif $os ~~ /darwin/  { $arch eq 'arm64' ?? 'MacOSX-ARM64' !! 'MacOSX-x86-64' }
            elsif $os ~~ /macos/   { $arch eq 'arm64' ?? 'MacOSX-ARM64' !! 'MacOSX-x86-64' }
            elsif $os ~~ /linux/   { $arch eq 'arm64' ?? 'Linux-ARM64'  !! 'Linux-x86-64' }
            else                   { '' }
        };
        return Nil unless $dir.chars;
        my $binary = $*DISTRO.is-win ?? 'ollama.exe' !! 'ollama';
        my $path = $!root.add('resources').add($dir).add($binary);
        $path if $path.e && $path.f;
    }

    method resolve(:$prefer-system) {
        my $use-system = $prefer-system // self.use-system;
        my $system     = self.system-path;
        my $bundled    = self.bundled-path;

        if $use-system && $system.defined {
            return $system;
        }
        with $bundled {
            return $bundled;
        }
        if $use-system && !$system.defined {
            note "System ollama not found. Install from https://ollama.com/download or toggle use-system-ollama.";
        }
        Nil;
    }
}