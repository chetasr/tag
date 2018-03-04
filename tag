#!/usr/bin/python

# Import acoustID library
import acoustid

# Import MP3 tagging library
from mutagen.mp3 import MP3
from mutagen.id3 import ID3, APIC, error
from mutagen.easyid3 import EasyID3
import mutagen.id3

# Import other necessary libraries
import sys
import os
import json
import requests
import shutil
import pickle
from difflib import SequenceMatcher
import argparse

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
    results = requests.get(
        'http://coverartarchive.org/release-group/' + mbid + '/')

    resjson = json.loads(results.text)

    imgres = requests.get(resjson['images'][0]['image'], stream=True)
    with open('example.jpg', 'wb') as f:
        print(bcolors.HEADER + 'Downloading cover art...' + bcolors.ENDC)
        shutil.copyfileobj(imgres.raw, f)

# Create function to tag file with data


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
    audiofile.save()

    # Rename file
    artlist = artist.split('; ')
    if len(artlist) > 1:
        artists = artlist[0] + ' feat. '
        artists = artists + ', '.join(artlist[1:])
    else:
        artists = artlist[0]
    os.rename(fn, artists + ' - ' + title + '.mp3')

# Create function to get acoustID data from MP3 file


def fingerprint(fn, auto=False):
    # fn - Filename
    artists = []
    title = ''
    album = ''
    mbid = ''
    mp3file = EasyID3(fn)
    count = 0
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

    try:
        if results['results'] == []:
            print("Could not find any metadata!")
            title = raw_input("Enter title: ")
            artists = raw_input("Enter artists (separated by ;): ")
            album = raw_input("Enter album name: ")
            artlist = artists.split('; ')
            if len(artlist) > 1:
                artists = artlist[0] + ' feat. '
                artists = artists + ', '.join(artlist[1:])
            else:
                artists = artlist[0]
            return title, artists, album, ''
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
        if similar(x['title'], mp3file['title'][0]) >= 0.5:
            dcho = count
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
        if len(artlist) > 1:
            artists = artlist[0] + ' feat. '
            artists = artists + ', '.join(artlist[1:])
        else:
            artists = artlist[0]
    else:
        artists = []
        title = results['results'][0]['recordings'][choice]['title']
        for x in results['results'][0]['recordings'][choice]['artists']:
            artists.append(x['name'])
        artists = '; '.join(artists)
        artlist = artists.split('; ')
        if len(artlist) > 1:
            artists = artlist[0] + ' feat. '
            artists = artists + ', '.join(artlist[1:])
        else:
            artists = artlist[0]

    count = 0
    dcho = 0
    if not auto:
        print(bcolors.WARNING + "Choose album:" + bcolors.ENDC)
    for x in albres['results'][0]['releasegroups']:
        if not auto:
            print(str(count) + '. ' + x['title'] + ' -',)
        try:
            if not auto:
                print(x['type'])
            if similar(x['title'], title) >= 0.5 and x['type'] == 'Single':
                dcho = count
        except:
            if not auto:
                print('Album')
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

    print(bcolors.WARNING + title + ' - ' + artists + ' - ' + album + bcolors.ENDC)

    return title, artists, album, mbid


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
                print(bcolors.HEADER + 'Now tagging - ' + x + bcolors.ENDC)
                title, artist, album, mbid = fingerprint(x, args.auto)
                getCoverArt(mbid)
                data = {'title': title, 'artist': artist, 'album': album}
                tagFile(x, data)
                print(bcolors.OKGREEN + 'Tagging successful' + bcolors.ENDC)
        else:
            print(bcolors.HEADER + 'Now tagging - ' +
                  sys.argv[1] + bcolors.ENDC)
            title, artist, album, mbid = fingerprint(sys.argv[1])
            getCoverArt(mbid)
            data = {'title': title, 'artist': artist, 'album': album}
            tagFile(sys.argv[1], data)
            print(bcolors.OKGREEN + 'Tagging successful' + bcolors.ENDC)
    except KeyboardInterrupt:
        print()
        print(bcolors.WARNING + 'Quitting tag' + bcolors.ENDC)
        exit(0)
    except Exception:
        print()
        print('An error occured')
        exit(1)
