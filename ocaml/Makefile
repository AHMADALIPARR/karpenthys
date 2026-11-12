OCAMLOPT ?= ocamlopt

karp: json.ml karp.ml main.ml
	$(OCAMLOPT) -o karp json.ml karp.ml main.ml

clean:
	rm -f karp *.cmi *.cmx *.o

.PHONY: clean
