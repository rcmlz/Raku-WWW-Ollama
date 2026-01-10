# WWW::Ollama

Raku package for accessing [Ollama](https://ollama.com) models.

The implementation is based in the Ollama's API, [Ol1], and observing (and trying to imitate) the 
Ollama client of Wolfram Language.

The package has the following features:

- If `ollama` is not running the corresponding executable is found and started
- If a request specifies the use of a known Ollama "local-evaluation" model, but that model is not available locally, then the model is downloaded first 

-----

## Installation

From GitHub:

```
zef install https://github.com/antononcube/Raku-WWW-Ollama.git
```

From [Zef ecosystem](https://raku.land):

```
zef install WWW::Ollama
```

-----

## Usage examples

For detailed usage examples see:

- [Basic-usage.raku](./examples/Basic-usage.raku) (script)
- [Basic-usage.ipynb](./docs/Basic-usage.ipynb) (notebook)

-----

## CLI

The package provides the Command Line Interface (CLI) script `ollama-client` for making Ollama LLM generations.
Here is the usage message:

```shell
ollama-client --help
```

-----

## TODO

- [ ] TODO Implementation
  - [X] DONE Reasonable gists for the different objects.
  - [ ] TODO Refactor to simpler code
  - [ ] TODO Functional interface 
    - I.e. without the need to explicitly make a client object.
- [ ] TODO CLI
  - [X] DONE MVP
  - [ ] TODO Detect JSON file with valid chat records
  - [ ] TODO Detect JSON string with valid chat records
- [ ] TODO Unit tests
- [ ] TODO Documentation

-----

## References

[Ol1] ["Ollama API"](https://github.com/ollama/ollama/blob/main/docs/api.md).
