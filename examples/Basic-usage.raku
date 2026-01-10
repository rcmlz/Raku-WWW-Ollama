#!/usr/bin/env raku
use v6.d;

use WWW::Ollama::Client;

#my $ollama = WWW::Ollama::Client.new(host => 'localhost', :11434port);
my $ollama = WWW::Ollama::Client.new(:ensure-running);

say (:$ollama);

#----------------------------------------------------------------------------------------------------
# Models
#----------------------------------------------------------------------------------------------------
say '-' x 100;
say "Models:";
my @models = |$ollama.list-models;

.say for @models;

#----------------------------------------------------------------------------------------------------
# Completion
#----------------------------------------------------------------------------------------------------
say '-' x 100;
say "Completion:";

my %body =
        model => 'gemma3:1b',
        prompt => "How many people live in Brazil?",
        :!stream
        ;

my $ans = |$ollama.completion(%body);

say $ans;

#----------------------------------------------------------------------------------------------------
# Chat
#----------------------------------------------------------------------------------------------------
say '-' x 100;
say "Chat answer:";

my %chat-body =
        model => 'gemma3:1b',
        messages => [{role => "user", content => "How many people live in Brazil?"},]
        ;

my $chat-ans = |$ollama.chat(%chat-body);

say $chat-ans;