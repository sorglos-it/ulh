# Third-party components

| Component | Where | Version | License | Source |
|---|---|---|---|---|
| yq | `apps/cli/vendor/yq/` (`yq-amd64`, `yq-arm64`, `yq-arm`, `yq-386`) | 4.52.4 | MIT | https://github.com/mikefarah/yq |

ulh reads its YAML files with yq and picks the binary that fits the processor.
The binaries are copied by hand and never changed. To update them: take
`yq_linux_amd64`, `yq_linux_arm64`, `yq_linux_arm` and `yq_linux_386` from a yq
release, rename them as above and change the version here. yq itself contains
further open-source Go modules; their licenses are listed in the yq repository.

## yq - MIT License

Copyright (c) 2017 Mike Farah

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
