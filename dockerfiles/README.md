# Docker files for Doris components



Base on https://github.com/apache/doris/tree/master/docker and optimize the entrypoint of FE, BE and make the resulting image support multiple architectures. 



### Build Steps

Take FE as an example:

1. Make sure docker is installed and buildx is enabled.

2. Create a cross-platform docker builder for amd64 and arm64:

   ```bash
   docker buildx create --name doris-buider --use --platform linux/amd64,linux/arm64
   ```

3. Download the corresponding FE binary package to the `fe/resources` directory, including x64 and arm versions;

   https://doris.apache.org/download/

4. Build cross-platform arch docker image:

   ```bash
   cd fe
   docker buildx build --platform linux/amd64,linux/arm64 -t apache/doris-fe:1.2.3 .
   ```



### TODO

Improve the [multi-stage build process](https://docs.docker.com/build/building/multi-stage/) for docker from source code compilation.