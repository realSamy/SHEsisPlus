# ==========================================
# Stage 1: Build the SHEsis C++ Core Binary
# ==========================================
FROM ubuntu:16.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libboost-all-dev \
    libarmadillo-dev \
    libmlpack-dev \
    libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY . .

# Compile SHEsis binary (excluding unit test files)
RUN g++ -O3 -std=c++11 -D__STDC_LIMIT_MACROS -D__STDC_FORMAT_MACROS -Wno-parentheses \
    -I/usr/include/libxml2 \
    main.cpp HaplotypeLD.cpp SHEsisData.cpp fisher.cpp utility.cpp \
    AssociationTest.cpp HWETest.cpp LDTest.cpp QTL.cpp HaplotypeBase.cpp \
    Haplotype.cpp HaplotypeEM.cpp IndexingVariables.cpp ArrayStorage.cpp \
    System.cc Solver.cc Options.cc BMP.cpp font.cpp minifont.cpp \
    CreatHtmlTable.cpp linear.cpp regression.cpp logistic.cpp \
    MarkerRegression.cpp GeneInteractionQTL.cpp GeneInteractionBinary.cpp GeneInteraction.cpp \
    -o SHEsis -lmlpack -larmadillo -lboost_program_options -lxml2

# ==========================================
# Stage 2: Runtime Environment (Web UI & API)
# ==========================================
FROM ubuntu:16.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    xz-utils \
    ca-certificates \
    libarmadillo6 \
    libmlpack1 \
    libboost-program-options1.58.0 \
    libxml2 \
    && rm -rf /var/lib/apt/lists/*

# Install legacy Node.js 10 runtime for compatibility with Express 3.x / Kue 0.6
RUN curl -fsSL https://nodejs.org/dist/v10.24.1/node-v10.24.1-linux-x64.tar.xz | tar -xJ -C /usr/local --strip-components=1

WORKDIR /app/SHEsisWebServer

# Install Node dependencies (including unlisted runtime deps in package.json)
COPY SHEsisWebServer/package.json .
RUN npm install && npm install shelljs@^0.8.0 mongodb@^2.2.36 --save

# Copy web server source code
COPY SHEsisWebServer/ .

# Install compiled SHEsis binary into bin/
COPY --from=builder /build/SHEsis ./bin/SHEsis
RUN chmod +x ./bin/SHEsis

# Patch hardcoded database/redis connections to support environment variables
RUN sed -i "s/kue.createQueue()/kue.createQueue({ redis: { host: process.env.REDIS_HOST || 'localhost', port: parseInt(process.env.REDIS_PORT || '6379') } })/g" SHEsisServer.js && \
    sed -i "s/new Server('localhost',27017/new Server(process.env.MONGO_HOST || 'localhost', parseInt(process.env.MONGO_PORT || '27017')/g" SHEsisServer.js

# Ensure execution and temp result directories exist
RUN mkdir -p public/tmp && chmod -R 777 public/tmp

EXPOSE 5903

CMD ["node", "SHEsisServer.js"]
