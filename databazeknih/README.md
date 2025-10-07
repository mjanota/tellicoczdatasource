# Czech Book Database Search - Python Version

This is a modernized Python version of the original Perl script for searching the Czech book database (databazeknih.cz) and outputting results in Tellico XML format. The script has been completely refactored with improved HTML parsing, professional logging, and comprehensive field extraction.

## Dependencies

The script requires the following Python packages:
- `requests` - For HTTP requests
- `beautifulsoup4` - For HTML parsing  
- `lxml` - XML parser for BeautifulSoup

## Installation

### Using uv (recommended)

1. Install uv if you haven't already:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

2. Install the project with dependencies:
```bash
uv sync
```

### Using traditional pip

1. Create a virtual environment:
```bash
python3 -m venv .venv
source .venv/bin/activate
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

## Usage

### Using uv (recommended)

```bash
uv run databazeknih-search -t "Hobbit"
```

Or directly with the script:
```bash
uv run python databazeknih_search_my.py -t "Hobbit"
```

### Using traditional Python

```bash
python databazeknih_search_my.py -t "Hobbit"
```

### Command line options:
- `-t, --title` - Title of the book (required)
- `--debug` - Enable debug mode with detailed logging (optional)

## Features

### Extracted Book Information
The script extracts comprehensive metadata from databazeknih.cz:

- **Basic Info**: Title, original title, subtitle
- **Authors**: Primary authors and translators
- **Publication**: Publisher, publication year, copyright year, edition
- **Physical**: Binding type, page count, ISBN
- **Additional**: Language, series/edition info, purchase price
- **Content**: Book description/comments
- **Media**: Cover image (embedded as base64)
- **Reference**: Direct link to the book page

### Technical Features
- **Modern HTML Parsing**: Uses BeautifulSoup with elegant CSS selectors and find methods
- **Professional Logging**: Configurable logging system with debug mode support
- **Robust Error Handling**: Graceful handling of missing data and network issues
- **Respectful Web Scraping**: Proper User-Agent headers and request delays
- **Clean Code**: Simplified architecture with eliminated global variables

## Example

### Basic Usage
```bash
uv run databazeknih-search -t "Hobbit" > results.xml
```

### Debug Mode
```bash
uv run databazeknih-search -t "Hobbit" --debug > results.xml
```

### Using traditional Python
```bash
python databazeknih_search_my.py -t "Hobbit" > results.xml
python databazeknih_search_my.py -t "Hobbit" --debug > results.xml  # with debug logging
```

This will search for books with "Hobbit" in the title and output the results in Tellico XML format. Debug mode provides detailed logging information to stderr.

## Major Improvements from Original Perl Version

### Code Quality & Architecture
- **Simplified Structure**: Eliminated global variables and complex state management
- **Modern Python**: Replaced outdated libraries with modern equivalents:
  - `wget` → Python `requests` library
  - `HTML::TreeBuilder` → `BeautifulSoup4` with CSS selectors
  - `XML::Writer` → `xml.etree.ElementTree`
  - `Getopt::Std` → `argparse`
- **Clean Functions**: Each parsing function focused on single responsibility

### HTML Parsing Improvements
- **Elegant BeautifulSoup Methods**: Replaced regex-based parsing with robust CSS selectors
- **Systematic Category Parsing**: Complete rewrite of `get_data_from_more` function using BeautifulSoup's `find_all` with text parameter
- **Robust Data Extraction**: Better handling of missing or malformed HTML structures

### Logging & Debugging
- **Professional Logging System**: Configurable logging with proper levels (INFO, DEBUG, ERROR)
- **Debug Mode**: Command-line `--debug` flag for detailed troubleshooting
- **Clean Output Separation**: XML output to stdout, logging to stderr

### Data Extraction
- **Comprehensive Field Coverage**: Extracts all available metadata including original titles, copyright years, detailed descriptions
- **Better Error Recovery**: Graceful handling of missing fields without script failure
- **Enhanced Image Handling**: Robust cover image download and base64 encoding

## Technical Notes

- **Output Format**: XML in Tellico format sent to stdout
- **Logging**: Error messages and debug information sent to stderr  
- **Image Handling**: Book cover images downloaded and embedded as base64 in XML
- **Temporary Files**: Automatic cleanup of any temporary files created
- **Web Scraping Ethics**: Respectful delays between requests and proper User-Agent headers
- **Error Resilience**: Script continues processing even when individual fields fail to extract

## Development Status

This version represents a complete modernization of the original Perl script with:
- ✅ Simplified and clean codebase  
- ✅ Professional logging system
- ✅ Modern HTML parsing with BeautifulSoup
- ✅ Comprehensive field extraction
- ✅ Debug mode for troubleshooting
- ✅ Robust error handling

The script successfully extracts all major book metadata available from databazeknih.cz and formats it correctly for Tellico import.