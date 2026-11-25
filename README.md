# v4vendetta

**v4vendetta** is a scoped parameter URL collector written in Bash. It automates web crawling, URL collection, parameter URL extraction, and directory URL discovery using [Katana](https://github.com/projectdiscovery/katana).

Designed for authorized security assessments, v4vendetta helps security researchers and penetration testers identify potentially interesting URLs within a defined domain scope.

It can also integrate with [DeadShot](https://github.com/G01d3nW01f/deadshot), allowing previously discovered and DNS-resolved subdomains to be used as crawl targets.

## Features

- **Scoped Web Crawling**
  - Crawls the specified target hostname or an explicitly defined root domain.
  - Restricts collected URLs to the authorized domain scope.

- **DeadShot Integration**
  - Accepts a DeadShot alive-host list as an optional input.
  - Automatically converts in-scope hostnames into HTTPS crawl seeds.
  - Rejects hosts outside the configured root domain.

- **Katana Integration**
  - Uses [Katana](https://github.com/projectdiscovery/katana) for web crawling.
  - Enables JavaScript crawling.
  - Uses a depth limit of 3.
  - Applies request concurrency and rate limits.

- **Parameter URL Collection**
  - Identifies URLs containing query parameters.
  - Saves parameter URLs separately for further analysis.

- **Directory URL Collection**
  - Identifies URLs with paths ending in `/`.
  - Saves directory URLs independently from parameter URLs.

- **Domain Scope Enforcement**
  - Validates hostnames before accepting URLs.
  - Uses exact domain-boundary matching to prevent unrelated domains from entering the results.

- **Deduplication**
  - Removes duplicate parameter URLs and directory URLs.

- **Daily Output Files**
  - Organizes results by root domain.
  - Uses date-based filenames for daily collection.

## Requirements

The following tools must be installed:

| Tool | Purpose |
|------|---------|
| Bash | Script execution |
| Katana | Web crawling and URL discovery |
| awk | Text processing |
| grep | Pattern matching |
| sort | Sorting and deduplication |
| date | Date generation |
| mkdir | Directory creation |
| mktemp | Temporary directory creation |

### Installing Katana

Install Katana using Go:

```bash
go install github.com/projectdiscovery/katana/cmd/katana@latest
```

Make sure the Go binary directory is available in your environment.

Verify the installation:

```bash
katana -version
```

## Installation

Clone the repository:

```bash
git clone https://github.com/G01d3nW01f/v4vendetta.git

cd v4vendetta
```

Make the script executable:

```bash
chmod +x v4vendetta.sh
```

## Usage

```bash
./v4vendetta.sh <targetdomain> [deadshot_alive_file]
```

### Basic Usage

Crawl a specific hostname:

```bash
./v4vendetta.sh www.example.com
```

When no input file is provided, v4vendetta uses the target hostname as the crawl seed.

The script creates an HTTPS seed for the specified hostname.

### DeadShot Integration

Use a DeadShot alive-host list as crawl input:

```bash
./v4vendetta.sh www.example.com ./deadshot_results/example.com/latest_alive_list.txt
```

v4vendetta reads the supplied host list, validates each hostname, and creates HTTPS crawl seeds for hosts within the configured root domain.

### Explicit Root Domain

By default, the target hostname itself is used as the root domain.

To crawl subdomains under a common root domain, specify `ROOT_DOMAIN`:

```bash
ROOT_DOMAIN=example.co.jp ./v4vendetta.sh www.example.co.jp
```

This allows the script to accept URLs from:

```text
example.co.jp
www.example.co.jp
api.example.co.jp
dev.example.co.jp
staging.example.co.jp
```

The root domain must be a valid FQDN, and the target hostname must belong to the specified root domain.

## Workflow

v4vendetta performs the following operations:

1. Validate command-line arguments.
2. Normalize the target URL and hostname.
3. Determine the root domain.
4. Validate the target against the configured scope.
5. Check required dependencies.
6. Validate the optional DeadShot input file.
7. Create the output directory.
8. Build crawl seeds from the target hostname or DeadShot alive-host list.
9. Remove duplicate crawl seeds.
10. Execute Katana with the configured crawling options.
11. Validate discovered HTTP/HTTPS URLs.
12. Extract hostnames and enforce domain scope restrictions.
13. Identify URLs containing query parameters.
14. Identify directory URLs ending in `/`.
15. Deduplicate collected URLs.
16. Save the final results.
17. Display the crawl summary.

## Katana Configuration

v4vendetta executes Katana with the following options:

| Option | Value | Description |
|--------|-------|-------------|
| `-list` | Seeds file | Reads crawl targets from a file |
| `-silent` | Enabled | Suppresses unnecessary output |
| `-no-color` | Enabled | Disables colored output |
| `-jc` | Enabled | Enables JavaScript crawling |
| `-fs` | `rdn` | Applies the registered-domain field scope |
| `-d` | `3` | Sets the maximum crawl depth |
| `-c` | `10` | Sets request concurrency |
| `-rl` | `5` | Limits request rate |
| `-timeout` | `10` | Sets request timeout |
| `-retry` | `1` | Sets the retry count |
| `-f` | `qurl` | Uses query URL output format |
| `-o` | Raw output file | Writes discovered URLs to a file |

## Output Structure

v4vendetta automatically creates a results directory for each root domain.

Example:

```text
v4vendetta_results/
└── example.com/
    ├── 20261125_params.txt
    └── dirs_20261125.txt
```

### Output Files

| File | Description |
|------|-------------|
| `YYYYMMDD_params.txt` | Unique URLs containing query parameters |
| `dirs_YYYYMMDD.txt` | Unique directory URLs with paths ending in `/` |

### Parameter URL Examples

```text
https://example.com/search?q=test
https://example.com/products?id=123
https://example.com/api/users?page=2
https://example.com/login?redirect=/dashboard
```

These URLs are collected when they contain a non-empty query string.

### Directory URL Examples

```text
https://example.com/
https://example.com/admin/
https://example.com/api/
https://example.com/static/
```

Directory URLs are identified by paths ending in `/`.

Note that parameter URLs and directory URLs are collected independently. A URL may appear in both output files if it satisfies both conditions.

## Domain Scope Validation

Domain scope enforcement is one of the core features of v4vendetta.

The script checks whether each discovered hostname:

- Exactly matches the configured root domain.
- Ends with the configured root domain preceded by a dot.

For example, with `example.com` as the root domain:

| Hostname | Result |
|----------|--------|
| `example.com` | Accepted |
| `www.example.com` | Accepted |
| `api.example.com` | Accepted |
| `dev.api.example.com` | Accepted |
| `example.com.evil.com` | Rejected |
| `notexample.com` | Rejected |
| `evil-example.com` | Rejected |

This boundary-based validation prevents unrelated hostnames from entering the collected results.

### Default Scope Behavior

If `ROOT_DOMAIN` is not specified, the exact target hostname becomes the root domain.

For example:

```bash
./v4vendetta.sh www.example.com
```

The default scope is:

```text
www.example.com
```

Other subdomains, such as `api.example.com`, will not be accepted.

To include them, explicitly configure the root domain:

```bash
ROOT_DOMAIN=example.com ./v4vendetta.sh www.example.com
```

## DeadShot Integration Workflow

v4vendetta can be used together with DeadShot to create a simple domain intelligence and URL collection workflow.

```text
                 +----------------------+
                 |      DeadShot        |
                 | Subdomain Discovery   |
                 +----------+-----------+
                            |
                            v
                 +----------------------+
                 |    DNS Resolution    |
                 |        dnsx          |
                 +----------+-----------+
                            |
                            v
                 +----------------------+
                 |   Alive Host List    |
                 | latest_alive_list.txt|
                 +----------+-----------+
                            |
                            v
                 +----------------------+
                 |     v4vendetta       |
                 |    Host Filtering   |
                 +----------+-----------+
                            |
                            v
                 +----------------------+
                 |    Katana Crawling   |
                 +----------+-----------+
                            |
                            v
                 +----------------------+
                 |   URL Extraction     |
                 +----------+-----------+
                            |
                 +----------+-----------+
                 |                      |
                 v                      v
       +------------------+   +------------------+
       | Parameter URLs   |   | Directory URLs   |
       | *_params.txt     |   | dirs_*.txt       |
       +------------------+   +------------------+
```

### Example Combined Execution

First, execute DeadShot:

```bash
./deadshot.sh example.com
```

Then use its latest alive-host snapshot with v4vendetta:

```bash
ROOT_DOMAIN=example.com ./v4vendetta.sh www.example.com ./deadshot_results/example.com/latest_alive_list.txt
```

This workflow allows v4vendetta to crawl multiple DNS-resolved subdomains discovered by DeadShot while enforcing the configured root-domain boundary.

## Example Output

```text
[v4vendetta] Target URL:  https://www.example.com
[v4vendetta] Target host: www.example.com
[v4vendetta] Scope root:  example.com
[v4vendetta] Loading hosts from: ./alive_list.txt
[v4vendetta] Crawl seeds: 18
[v4vendetta] Starting Katana crawl

[v4vendetta] Crawl completed
------------------------------------------
Target        : www.example.com
Scope root    : example.com
Raw URLs      : 250
Parameter URLs: 42
Directory URLs: 35
Params output : ./v4vendetta_results/example.com/20261125_params.txt
Dirs output   : ./v4vendetta_results/example.com/dirs_20261125.txt
------------------------------------------
```

*Note: This is an illustrative example. Actual results depend on the target domain, available hosts, and crawling behavior.*

## Limitations

- URL discovery depends on the pages and endpoints accessible to Katana.
- JavaScript crawling does not guarantee discovery of every dynamically generated endpoint.
- Only URLs returned by Katana are considered.
- Parameter URL extraction requires a non-empty query string.
- Directory URL extraction only identifies paths ending in `/`.
- The script does not test parameter values or identify vulnerabilities.
- The script does not perform directory brute-forcing.
- The default scope is the exact target hostname unless `ROOT_DOMAIN` is explicitly specified.
- Only HTTP and HTTPS URLs without userinfo or explicit ports are accepted.
- The `-fs rdn` Katana filtering behavior may affect which URLs are discovered before the script's own scope validation.
- Existing daily output files are replaced after a successful crawl and filtering operation.

## Security Considerations

v4vendetta is intended for authorized web reconnaissance and internal security assessments.

- Only crawl domains that you own or have explicit permission to assess.
- Crawling generates HTTP/HTTPS requests to target servers.
- Respect the target's rate limits and operational policies.
- Review the scope before supplying a DeadShot host list.
- Use `ROOT_DOMAIN` carefully to avoid including unintended subdomains.
- Ensure that crawling activities comply with applicable laws, agreements, and security policies.

## License

Specify your preferred license before distributing this project.

## Disclaimer

v4vendetta is provided for educational purposes, authorized security assessments, and internal domain intelligence operations.

The author assumes no responsibility for misuse or unauthorized activity performed using this tool.

**Use v4vendetta responsibly and only against domains for which you have explicit authorization.**
