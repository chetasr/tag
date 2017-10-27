# tag
command line mp3 tagger

## requirements
Use ```pip install -r requirements.txt``` to install the dependencies.
The project also needs the [Chromaprint](https://github.com/acoustid/chromaprint) tool to work.

## how to use
Run the script with your mp3 files
```
> ./tag -h
usage: tag [-h] [-a] file

positional arguments:
  file        file to tag

optional arguments:
  -h, --help  show this help message and exit
  -a, --auto  automatically tag without user input
```
You can also tag multiple files at once
```
 > ./tag all
```
Tag files automatically using the ```-a``` option
```
> ./tag -a my_music.mp3
```
