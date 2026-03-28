#! /usr/bin/env bash

MODEL=${1:-base}

if [[ "$(uname -o)" == "Darwin" ]]; then
  # see other models here -> https://huggingface.co/ggerganov/whisper.cpp/tree/main
  $HOME/bin/whisper.cpp/models/download-ggml-model.sh $MODEL.en

  $HOME/bin/whisper.cpp/build/bin/whisper-stream \
    -m $HOME/bin/whisper.cpp/models/ggml-$MODEL.en.bin \
    -t 8 \
    --step 500 \
    --length 5000
fi
