#!/usr/bin/env python3
"""
Czech book database search script - Python version
Converts Perl script to Python for searching databazeknih.cz
"""

import argparse
import requests
import sys
import logging
from bs4 import BeautifulSoup
import xml.etree.ElementTree as ET
import hashlib
import base64
import re
from urllib.parse import urljoin
import time

# Configure logging to stderr
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stderr)
    ]
)
logger = logging.getLogger(__name__)

class DatabazeknihSearch:
    def __init__(self):
        self.address = 'http://www.databazeknih.cz'
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        })

    def parse_arguments(self, args=None):
        """Parse command line arguments"""
        parser = argparse.ArgumentParser(description='Search Czech book database (databazeknih.cz)')
        parser.add_argument('-t', '--title', required=True, help='Title of the book')
        parser.add_argument('-d', '--debug', action='store_true', help='Enable debug logging')
        return parser.parse_args(args)

    def get_page_content(self, url):
        """Get webpage content using requests"""
        try:
            logger.debug(f"Fetching URL: {url}")
            response = self.session.get(url, timeout=30)
            response.encoding = 'utf-8'
            logger.debug(f"Successfully fetched {url}, status: {response.status_code}, content length: {len(response.text)}")
            return response.text
        except requests.RequestException as e:
            logger.error(f"Error fetching {url}: {e}")
            return None

    def get_refs(self, html):
        """Extract book references from search results"""
        if not html:
            return []

        soup = BeautifulSoup(html, 'html.parser')
        refs = []
        seen_refs = set()

        # Find all book links
        book_links = soup.find_all('a', {'class': 'new', 'type': 'book'})
        logger.debug(f"Found {len(book_links)} book links in search results")

        for link in book_links:
            href = link.get('href')
            if href and href not in seen_refs:
                logger.debug(f"Adding book reference: {href}")
                refs.append(href)
                seen_refs.add(href)

                # Get additional editions
                if href.endswith('/'):
                    book_id = href.rstrip('/').split('/')[-1]
                else:
                    book_id = href.split('/')[-1]

                # Remove query parameters if present
                book_id = book_id.split('?')[0]

                editions_url = f"{self.address}/dalsi-vydani/{book_id}"
                editions_html = self.get_page_content(editions_url)
                if editions_html:
                    editions_soup = BeautifulSoup(editions_html, 'html.parser')
                    edition_links = editions_soup.find_all('a', {'class': 'bigger', 'href': re.compile(r'dalsi-vydani')})

                    for elink in edition_links:
                        ehref = elink.get('href')
                        if ehref:
                            ehref = ehref.replace('dalsi-vydani', 'knihy')
                            if ehref not in seen_refs:
                                refs.append(ehref)
                                seen_refs.add(ehref)

        return refs

    def html2book(self, html, pmore_html, book_url, images):
        """Convert HTML content to book data dictionary"""
        if not html:
            return {}

        soup = BeautifulSoup(html, 'html.parser')
        book_data = {'link': book_url}

        # Remove unwanted content
        for ol_tag in soup.find_all('ol'):
            ol_tag.decompose()

        content = soup.find('div', {'id': 'content'})
        if not content:
            return book_data

        # Extract data from main page
        self.get_title(book_data, content)
        self.get_publisher(book_data, content)
        self.get_pub_year(book_data, content)

        # Extract original title and copyright year
        self.get_orig_title(book_data, content)

        # Extract data from "more info" page
        if pmore_html:
            pmore_soup = BeautifulSoup(pmore_html, 'html.parser')
            self.get_data_from_more(book_data, pmore_soup)

        # Get cover image
        img_tag = content.find('img', {'class': re.compile(r'kniha_img')})
        if img_tag and img_tag.get('src'):
            image_data = self.get_image(book_data, img_tag['src'])
            if image_data:
                images.append(image_data)

        return book_data

    def get_title(self, book_data, content):
        """Extract title and author information"""
        title_h1 = content.find('h1', {'class': 'oddown_five'})
        if not title_h1:
            return

        title_text = title_h1.get_text(strip=True)

        # Remove subtitle in em tag
        em_tag = title_h1.find('em')
        if em_tag:
            subtitle = em_tag.get_text(strip=True)
            title_text = title_text.replace(subtitle, '').strip()

        # Split title and original title
        if ' / ' in title_text:
            parts = title_text.split(' / ', 1)
            book_data['title'] = parts[0].strip()
            book_data['nazev-originalu'] = parts[1].strip()
        else:
            book_data['title'] = title_text

        # Get authors
        author_spans = content.find_all('span', {'class': 'author'})
        authors = []
        for span in author_spans:
            author_links = span.find_all('a')
            for link in author_links:
                author_name = link.get_text(strip=True)
                if author_name:
                    authors.append(author_name)

        if authors:
            book_data['author'] = authors

        # Get comments/description
        comment_p = content.find('p', {'class': 'new2 odtop'})
        if comment_p:
            comments = comment_p.get_text(strip=True)
            # Remove "... celý text" ending if present
            comments = re.sub(r'\.\.\. celý text.*$', '', comments).strip()
            book_data['comments'] = comments

    def get_publisher(self, book_data, content):
        """Extract publisher from 'more info' page"""
        if not content:
            return

        publisher_links = content.find_all('a', {'href': re.compile(r'nakladatelstvi')})
        publishers = [link.get_text(strip=True) for link in publisher_links if link.get_text(strip=True)]
        if publishers:
            book_data['publisher'] = publishers

    def get_pub_year(self, book_data, content):
        """Extract publication year from detail_description"""
        if not content:
            return

        detail_div = content.find('div', {'class': 'detail_description'})
        if not detail_div:
            return

        # Find span with class "category" containing "Vydáno" and get next span
        vydano_span = detail_div.find('span', {'class': 'category'}, string=lambda text: text and 'Vydáno' in text)
        if vydano_span:
            next_span = vydano_span.find_next_sibling('span')
            if next_span:
                year_match = re.search(r'(\d{4})', next_span.get_text())
                if year_match:
                    logger.info(f"Found publication year: {year_match.group(1)}")
                    book_data['pub_year'] = year_match.group(1)

    def get_orig_title(self, book_data, content):
        """Extract original title and copyright year"""
        if not content:
            return

        detail_div = content.find('div', {'class': 'detail_description'})
        if not detail_div:
            return

        # Find span with "Originální název:" and get the text after it
        orig_span = detail_div.find('span', {'class': 'category'}, string=lambda text: text and 'Originální název' in text)
        if orig_span:
            # Get all text content after the span until <br>
            current = orig_span.next_sibling
            title_parts = []
            year = None

            while current and current.name != 'br':
                if hasattr(current, 'get_text'):
                    text = current.get_text().strip()
                    if text and text != ',':
                        # Check if it's a year (4 digits)
                        year_match = re.search(r'(\d{4})', text)
                        if year_match and not title_parts:  # Year found but no title yet
                            continue
                        elif year_match and title_parts:  # Year found after title
                            year = year_match.group(1)
                        else:
                            title_parts.append(text)
                elif isinstance(current, str):
                    text = current.strip()
                    if text and text not in [',', ' ']:
                        # Check if it's a year
                        year_match = re.search(r'(\d{4})', text)
                        if year_match:
                            year = year_match.group(1)
                        else:
                            title_parts.append(text)
                current = current.next_sibling

            if title_parts:
                logger.info(f"Found original title: {' '.join(title_parts).strip()}")
                book_data['nazev-originalu'] = ' '.join(title_parts).strip()
            if year:
                logger.info(f"Found copyright year: {year}")
                book_data['cr_year'] = year

    def get_data_from_more(self, book_data, pmore):
        """Extract additional data from 'more info' page"""
        if not pmore:
            return

        # Find all category spans to extract data systematically

        if (pages_span := pmore.find('span', {'itemprop': 'numberOfPages'})):
            book_data['pages'] = pages_span.get_text(strip=True)
            logger.info("Found number of pages: %s", book_data['pages'])

        translators = [tr.get_text(strip=True) for tr in pmore.find_all('a', {'href': re.compile(r'prekladatele')})]
        if translators:
            book_data['prekladatel'] = translators
            logger.info("Found translators %s", ', '.join(translators))

        category_spans = pmore.find_all('span', class_='category')

        for category_span in category_spans:
            category_text = category_span.get_text(strip=True)

            # Find the corresponding data span/element after the category
            next_sibling = category_span.next_sibling

            # Skip whitespace and find the actual data element
            while next_sibling and isinstance(next_sibling, str) and next_sibling.strip() == '':
                next_sibling = next_sibling.next_sibling

            if not next_sibling:
                continue
            elif category_text == 'Jazyk vydání:':
                # Find next span with language
                lang_span = category_span.find_next_sibling('span')
                if lang_span:
                    book_data['language'] = lang_span.get_text(strip=True)

            elif category_text == 'Forma:':
                # Get the text directly after the category span
                if next_sibling and isinstance(next_sibling, str):
                    form_text = next_sibling.strip()
                    if form_text:
                        # Could map to binding or other field if needed
                        pass

            elif category_text == 'Vazba knihy:':
                # Get binding info - text directly after the category
                if next_sibling and isinstance(next_sibling, str):
                    binding_text = next_sibling.strip()
                    if binding_text:
                        book_data['binding'] = binding_text

            elif category_text == 'ISBN:':
                # Find ISBN span
                isbn_span = category_span.find_next_sibling('span')
                if isbn_span:
                    isbn_text = isbn_span.get_text(strip=True)
                    if isbn_text:
                        book_data['isbn'] = isbn_text

    def get_image(self, book_data, img_src):
        """Download and process book cover image"""
        if not img_src:
            return None

        # Handle relative URLs
        if img_src.startswith('/'):
            img_url = self.address + img_src
        elif img_src.startswith('http'):
            img_url = img_src
        else:
            img_url = urljoin(self.address, img_src)

        try:
            response = self.session.get(img_url, timeout=30)
            if response.status_code == 200:
                img_data = response.content

                # Determine image type
                img_type = 'jpg'
                if '.' in img_src:
                    img_type = img_src.split('.')[-1].split('?')[0].lower()

                # Generate image name using MD5 hash
                img_name = hashlib.md5(img_data).hexdigest() + '.' + img_type
                book_data['cover'] = img_name

                # Prepare image data for XML
                img_info = {
                    'format': img_type.lower(),
                    'id': img_name,
                    'width': 100,
                    'height': 150,
                    'data': base64.b64encode(img_data).decode('ascii')
                }

                return img_info
        except requests.RequestException as e:
            logger.error(f"Error downloading image {img_url}: {e}")

        return None

    def create_xml_output(self, books, images):
        """Generate XML output in Tellico format"""
        # Create root element
        root = ET.Element('tellico', 
                         syntaxVersion='9',
                         xmlns='http://periapsis.org/tellico/')

        # Collection element
        collection = ET.SubElement(root, 'collection', 
                                 title='My Books', 
                                 type='2')
        
        # Fields definition
        fields = ET.SubElement(collection, 'fields')
        
        # Define all the fields (same as in Perl script)
        field_definitions = [
            {'name': 'title', 'title': 'Název', 'category': 'Obecné', 'flags': '4', 'format': '4', 'type': '1'},
            {'name': 'author', 'title': 'Autor', 'category': 'Obecné', 'flags': '7', 'format': '2', 'type': '1'},
            {'name': 'nazev-originalu', 'title': 'Název originálu', 'category': 'Obecné', 'flags': '3', 'format': '4', 'type': '1'},
            {'name': 'subtitle', 'title': 'Podtitul', 'category': 'Obecné', 'flags': '0', 'format': '1', 'type': '1'},
            {'name': 'pur_price', 'title': 'Kupní cena', 'category': 'Publikování', 'flags': '0', 'format': '4', 'type': '1'},
            {'name': 'publisher', 'title': 'Vydavatel', 'category': 'Obecné', 'flags': '7', 'format': '4', 'type': '1'},
            {'name': 'edice', 'title': 'Edice', 'category': 'Obecné', 'flags': '6', 'format': '4', 'type': '1'},
            {'name': 'edition', 'title': 'Vydání', 'category': 'Publikování', 'flags': '1', 'format': '0', 'type': '6'},
            {'name': 'cr_year', 'title': 'Rok copyrightu', 'category': 'Publikování', 'flags': '3', 'format': '4', 'type': '6'},
            {'name': 'pub_year', 'title': 'Rok vydání', 'category': 'Publikování', 'flags': '2', 'format': '4', 'type': '6'},
            {'name': 'isbn', 'title': 'ISBN č. ', 'category': 'Publikování', 'flags': '0', 'format': '4', 'type': '1', 'description': 'Mezinárodní standardní knižní číslo'},
            {'name': 'binding', 'title': 'Vazba', 'category': 'Publikování', 'flags': '2', 'format': '4', 'type': '3', 'allowed': 'E-Book;Paperback;Žurnál;Časopis;Velký paperback;Vázaná;Brožovaná;Pevná vazba;vázaná;brožovaná'},
            {'name': 'pages', 'title': 'Stran', 'category': 'Publikování', 'flags': '0', 'format': '4', 'type': '6'},
            {'name': 'language', 'title': 'Jazyk originálu', 'category': 'Publikování', 'flags': '7', 'format': '4', 'type': '1'},
            {'name': 'prekladatel', 'title': 'Překladatel', 'category': 'Publikování', 'flags': '7', 'format': '2', 'type': '1'},
            {'name': 'comments', 'title': 'Téma', 'category': 'Téma', 'flags': '0', 'format': '4', 'type': '2'},
            {'name': 'cover', 'title': 'Přední obálka', 'category': 'Přední obálka', 'flags': '0', 'format': '4', 'type': '10'},
            {'name': 'link', 'title': 'Link', 'category': 'Obecné', 'flags': '0', 'format': '4', 'type': '7', 'description': 'Odkaz'},
        ]
        
        # Add field definitions to XML
        for field_def in field_definitions:
            field_elem = ET.SubElement(fields, 'field')
            for attr, value in field_def.items():
                field_elem.set(attr, value)
        
        # Add special fields
        default_field = ET.SubElement(fields, 'field', name='_default')
        
        # Add book entries
        for i, book in enumerate(books):
            entry = ET.SubElement(collection, 'entry', id=str(i))

            for key, value in sorted(book.items()):
                if isinstance(value, list):
                    # Multiple values (authors, publishers, etc.)
                    container = ET.SubElement(entry, key + 's')
                    for item in value:
                        item_elem = ET.SubElement(container, key)
                        item_elem.text = str(item) if item else ''
                else:
                    # Single value
                    elem = ET.SubElement(entry, key)
                    elem.text = str(value) if value else ''

        # Add images section
        if images:
            images_section = ET.SubElement(collection, 'images')
            for img in images:
                img_elem = ET.SubElement(images_section, 'image')
                img_data = img.pop('data')
                img_elem.text = img_data
                for attr, value in img.items():
                    img_elem.set(attr, str(value))

        # Generate XML string
        xml_str = ET.tostring(root, encoding='unicode', method='xml')

        # Add XML declaration and DOCTYPE
        xml_declaration = '<?xml version="1.0" encoding="UTF-8"?>'
        doctype = '<!DOCTYPE tellico PUBLIC "-//Robby Stephenson/DTD Tellico V9.0//EN" "http://periapsis.org/tellico/dtd/v9/tellico.dtd">'

        return xml_declaration + doctype + xml_str

    def search_books(self, title):
        """Main search function"""
        books = []
        images = []

        # Prepare search query
        search_query = title.replace(' ', '+')
        search_url = f"{self.address}/search?q={search_query}&hledat="

        logger.info(f"Searching for: {title}")
        logger.info(f"Search URL: {search_url}")

        # Get search results
        search_html = self.get_page_content(search_url)
        if not search_html:
            logger.error("Failed to get search results")
            return

        # Extract book references
        refs = self.get_refs(search_html)
        logger.info(f"Found {len(refs)} book references")

        if not refs:
            logger.warning("Could not find any books")
            return

        # Process each book
        for ref in refs:
            if ref.startswith('/'):
                ref = ref[1:]  # Remove leading slash

            book_url = f"{self.address}/{ref}"
            logger.info(f"Processing: {book_url}")

            # Get book page
            book_html = self.get_page_content(book_url)
            if not book_html:
                continue

            # Get "more info" page if book ID can be extracted
            pmore_html = None
            # Remove '?lang=cz' if present, then extract the trailing number
            ref_clean = re.sub(r'\?lang=cz$', '', ref)
            book_id_match = re.search(r'(\d+)$', ref_clean)
            if book_id_match:
                book_id = book_id_match.group(1)
                more_url = f"{self.address}/book-detail-more-info/{book_id}"
                pmore_html = self.get_page_content(more_url)

            # Parse book data
            book_data = self.html2book(book_html, pmore_html, book_url, images)
            if book_data:
                books.append(book_data)

            # Add small delay to be respectful to the server
            time.sleep(0.5)

        logger.info(f"Successfully processed {len(books)} books")

        # Generate and output XML
        if books:
            xml_output = self.create_xml_output(books, images)
            print(xml_output)

def main(args=None):
    """Main function"""
    searcher = DatabazeknihSearch()
    parsed_args = searcher.parse_arguments(args)
    
    # Set logging level based on debug argument
    if parsed_args.debug:
        logger.setLevel(logging.DEBUG)
        # Also set handler level to DEBUG
        for handler in logger.handlers:
            handler.setLevel(logging.DEBUG)
    
    if not parsed_args.title:
        logger.error("Title is required")
        sys.exit(1)
    
    searcher.search_books(parsed_args.title)

if __name__ == '__main__':
    main()
