#/bin/sh
cue export reg.cue -l _input: text: registers.csv --out yaml \
| sed -E "s/'!secret (.*)'/!secret \1/g" \
> ctc-ecozenith-i250.yaml
