FROM alpine:latest

# xz -> LZMA2
# gzip -> DEFLATE -> LZ77 and Huffman
# bzip2 -> RLE, BWT, MTF, and Huffman
# TODO: Add more recent compression algorithms to compare against
RUN apk add --no-cache xz \
  gzip \
  bzip2

# TODO: Write and run a script to test each of the algorithms
