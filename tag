#!/usr/bin/python

# Import acoustID library
import acoustid

# Import MP3 tagging library
from mutagen.mp3 import MP3
from mutagen.id3 import ID3, APIC, USLT, error
from mutagen.easyid3 import EasyID3
import mutagen.id3

# Import other necessary libraries
import sys
import os
import json
import requests
import pickle
from difflib import SequenceMatcher
import argparse
from tqdm import tqdm
from unidecode import unidecode

# Import colorama for fun
import colorama

# Declare important constants (API keys, etc.)
keys = pickle.load(open('keys.dat', 'rb'))
acoust_key = keys['acoust-key']
colorama.init()


def similar(a, b):
    a = a.lower()
    b = b.lower()
    return SequenceMatcher(None, a, b).ratio()


class bcolors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

# Create function to get cover art


def getCoverArt(mbid):
    # mbid - MusicBrainz ID

    if mbid is '':
        raw_input(
            'Download cover art and save as \'example.jpg\'. Press enter to continue tagging.')
        return

    response = requests.get('http://coverartarchive.org/release-group/' + mbid + '/front-1200', stream=True)

    with open("example.jpg", "wb") as handle:
        for data in tqdm(response.iter_content(), ascii=True, desc=bcolors.HEADER + "Downloading cover art" + bcolors.ENDC, dynamic_ncols=True, unit='byte', total=int(response.headers['content-length'])):
            handle.write(data)

# Create function to tag file with data

def getLyrics(title, artist):
    url = "https://api.lyrics.ovh/v1/{}/{}".format(unidecode(artist), unidecode(title))
    page = requests.get(url).json()
    if 'error' in page:
        print bcolors.WARNING + "Lyrics not found!" + bcolors.ENDC
        return ''
    else:
        print bcolors.OKGREEN + "Lyrics found!" + bcolors.ENDC
        return page['lyrics']

def tagFile(fn, data):
    # fn - Filename
    # data - Title, Artist and Cover Art
    audiofile = MP3(fn, ID3=EasyID3)
    audiofile.delete()
    audiofile.save()
    audiofile['title'] = data['title']
    audiofile['artist'] = data['artist']
    audiofile['albumartist'] = data['artist']
    audiofile['album'] = data['album']
    audiofile.save()

    # Adding cover art now
    audiofile = MP3(fn, ID3=ID3)
    audiofile.tags.add(
        APIC(
            encoding=3,  # 3 is for utf-8
            mime='image/jpeg',  # image/jpeg or image/png
            type=3,  # 3 is for the cover image
            desc=u'Cover',
            data=open('example.jpg').read()
        )
    )
    audiofile.tags.add(
        USLT(
            lang='eng',
            text=data['lyrics']
        )
    )

    audiofile.save()

    # Rename file
    os.rename(fn, data['artist'] + ' - ' + data['title'] + '.mp3')

# Create function to get acoustID data from MP3 file


def fingerprint(fn, auto=False):
    # fn - Filename
    artists = []
    title = ''
    album = ''
    mbid = ''
    mp3file = EasyID3(fn)
    count = 0
    main_artist = ''
    try:
        results = acoustid.match(acoust_key, fn, parse=False)   
        albres = acoustid.match(
            acoust_key, fn, meta='releasegroups', parse=False)
    except acoustid.NoBackendError:
        print(bcolors.FAIL + "Chromaprint tool not found" + bcolors.ENDC)
        sys.exit(1)
    except acoustid.FingerprintGenerationError:
        print(bcolors.FAIL + "Could not calculate fingerprint" + bcolors.ENDC)
        sys.exit(1)
    except acoustid.WebServiceError as exc:
        print(bcolors.FAIL + "Connection failed: " + bcolors.ENDC, exc.message)
        sys.exit(1)
    except Exception:
        print('An unknown error occurred')
        title = raw_input("Enter title: ")
        artists = raw_input("Enter artists (separated by ;): ")
        album = raw_input("Enter album name: ")
        artlist = artists.split('; ')
        main_artist = artlist[0]
        if len(artlist) > 1:
            artists = artlist[0] + ' feat. '
            artists = artists + ', '.join(artlist[1:])
        else:
            artists = artlist[0]
        return title, artists, album, '', main_artist

    try:
        try:
            if not results['results']:
                print("Could not find any metadata!")
                title = raw_input("Enter title: ")
                artists = raw_input("Enter artists (separated by ;): ")
                album = raw_input("Enter album name: ")
                artlist = artists.split('; ')
                main_artist = artlist[0]
                if len(artlist) > 1:
                    artists = artlist[0] + ' feat. '
                    artists = artists + ', '.join(artlist[1:])
                else:
                    artists = artlist[0]
                return title, artists, album, '', main_artist
        except KeyError:
            print("Error retrieving metadata")
            sys.exit(1)
        if not auto:
            print(bcolors.WARNING + "Choose music title: " + bcolors.ENDC)
        dcho = 0
        for x in results['results'][0]['recordings']:
            try:
                for y in x['artists']:
                    artists.append(y['name'])
            except:
                continue
            if not auto:
                print(str(count) + '. ' + '; '.join(artists) + ' - ' + x['title'])
            try:
                if similar(x['title'], mp3file['title'][0]) >= 0.5:
                    dcho = count
            except Exception:
                pass
            count = count + 1
            artists = []
        if not auto:
            print(str(count) + '. Manual entry')
        if auto:
            choice = dcho
        else:
            choice = raw_input("Enter choice [" + str(dcho) + "]: ")
            if choice == '':
                choice = dcho
        choice = int(choice)
        if choice == count:
            title = raw_input("Enter title: ")
            artists = raw_input("Enter artists (separated by ;): ")
            artlist = artists.split('; ')
            main_artist = artlist[0]
            if len(artlist) > 1:
                artists = artlist[0] + ' feat. '
                artists = artists + ', '.join(artlist[1:])
            else:
                artists = artlist[0]
        else:
            title = results['results'][0]['recordings'][choice]['title']
            if 'joinphrase' in results['results'][0]['recordings'][choice]['artists'][0].keys():
                joinphrase = results['results'][0]['recordings'][choice]['artists'][0]['joinphrase']
            for x in results['results'][0]['recordings'][choice]['artists']:
                artists.append(x['name'])
            artists = '; '.join(artists)
            artlist = artists.split('; ')
            main_artist= artlist[0]
            if len(artlist) > 1:
                artists = artlist[0] + joinphrase
                artists = artists + ', '.join(artlist[1:])
            else:
                artists = artlist[0]

        count = 0
        dcho = 0
        if not auto:
            print(bcolors.WARNING + "Choose album:" + bcolors.ENDC)
        for x in albres['results'][0]['releasegroups']:
            try:
                if not auto:
                    print(str(count) + '. ' + x['title'] + ' - ' + x['type'])
                if similar(x['title'], title) >= 0.5 and x['type'] == 'Single':
                    dcho = count
            except:
                if not auto:
                    print(str(count) + '. ' + x['title'] + ' - ' + 'Album')
                pass
            count = count + 1
        if not auto:
            print(str(count) + '. Manual entry')
        if auto:
            choice = dcho
        else:
            choice = raw_input("Enter choice [" + str(dcho) + "]: ")
            if choice == '':
                choice = dcho
        choice = int(choice)
        if choice == count:
            album = raw_input("Enter album name: ")
        else:
            album = albres['results'][0]['releasegroups'][choice]['title']
            mbid = albres['results'][0]['releasegroups'][choice]['id']

    except Exception:
        print('An unknown error occurred')
        title = raw_input("Enter title: ")
        artists = raw_input("Enter artists (separated by ;): ")
        album = raw_input("Enter album name: ")
        artlist = artists.split('; ')
        main_artist = artlist[0]
        if len(artlist) > 1:
            artists = artlist[0] + ' feat. '
            artists = artists + ', '.join(artlist[1:])
        else:
            artists = artlist[0]
        return title, artists, album, '', main_artist

    print(bcolors.WARNING + title + ' - ' + artists + ' - ' + album + bcolors.ENDC)

    return title, artists, album, mbid, main_artist


# Main function
if __name__ == '__main__':
    try:
        parser = argparse.ArgumentParser()
        parser.add_argument("file", help='file to tag')
        parser.add_argument(
            '-a', "--auto", help='automatically tag without user input', action='store_true')
        args = parser.parse_args()
        if args.file == 'all':
            for x in [f for f in os.listdir(os.getcwd()) if f[-4:] == '.mp3']:
                try:
                    print(bcolors.HEADER + 'Now tagging - ' + x + bcolors.ENDC)
                    title, artist, album, mbid, main_artist = fingerprint(x, args.auto)
                    lyrics = getLyrics(title, main_artist)
                    getCoverArt(mbid)
                    data = {'title': title, 'artist': artist, 'album': album, 'lyrics': lyrics}
                    tagFile(x, data)
                    print(bcolors.OKGREEN + 'Tagging successful' + bcolors.ENDC)
                except Exception as e:
                    print("An error occured")
                    print(e)
        else:
            print(bcolors.HEADER + 'Now tagging - ' +
                  sys.argv[1] + bcolors.ENDC)
            title, artist, album, mbid, main_artist = fingerprint(sys.argv[1])
            lyrics = getLyrics(title, main_artist)
            getCoverArt(mbid)
            data = {'title': title, 'artist': artist, 'album': album, 'lyrics': lyrics}
            tagFile(sys.argv[1], data)
            print(bcolors.OKGREEN + 'Tagging successful' + bcolors.ENDC)
    except KeyboardInterrupt:
        print()
        print(bcolors.WARNING + 'Quitting tag' + bcolors.ENDC)
        exit(0)
    except Exception as e:
        print(e)
        print('An error occured')
        exit(1)
