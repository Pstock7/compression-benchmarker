FROM alpine:latest

# xz -> LZMA2
# gzip -> DEFLATE -> LZ77 and Huffman
# bzip2 -> RLE, BWT, MTF, and Huffman
# zstd -> LZ77, entropy-coding, Huffman and FSE, tANS
RUN apk add --no-cache xz \
  gzip \
  bzip2 \
  zstd \
  wget \
  unzip \
  bc \
  bash \
  coreutils

# Create directories for results and data
RUN mkdir -p /results /data

# Copy the benchmark script
COPY compression_benchmark.sh /compression_benchmark.sh
RUN chmod +x /compression_benchmark.sh

# Run the benchmark script
CMD ["/compression_benchmark.sh"]
