#!/usr/bin/env python3

import concurrent.futures
import copy
import enum
import glob
import regex as re
import snowballstemmer

PACKAGE_DIR = '/var/lib/apt/lists'
PACKAGE_PATTERN = '*Packages'

@enum.unique
class Kind(enum.Enum):
    ConsoleApp = enum.auto()
    GuiApp = enum.auto()
    Library = enum.auto()
    Font = enum.auto()
    Data = enum.auto()
    Documentation = enum.auto()
    Unknown = enum.auto()

class Deb:

    def __init__(self):
        self.clear()

    @property
    def valid(self):
        return bool(self.name) and bool(self.description)

    def clear(self):
        self.name = ''
        self.ver = ''
        self.section = ''
        self.description = ''
        self.url = ''
        self.tags = set()
        self.size = 0
        self.kind = Kind.Unknown

class State:

    def __init__(self):
        self.inDescription = False
        self.inContinuation = False

class Model:

    def __init__(self, maxDebNamesForWord):
        self.debForName = {} # key = name, value = Deb
        self.namesForWord = {} # key = word, value = set of Deb names
        self.maxDebNamesForWord = maxDebNamesForWord

    def __len__(self):
        return len(self.debForName)

    def readPackages(self):
        try:
            filenames = glob.iglob(f'{PACKAGE_DIR}/{PACKAGE_PATTERN}')
            with concurrent.futures.ProcessPoolExecutor() as executor:
                for debs in executor.map(self.readPackageFile, filenames):
                    for deb in debs:
                        self.debForName[deb.name] = deb
        except OSError as err:
            print(err)

    def readPackageFile(self, filename):
        try:
            state = State()
            debs = []
            deb = Deb()
            with open(filename, 'rt', encoding='utf-8') as file:
                for lino, line in enumerate(file, 1):
                    self.readPackageLine(filename, lino, line, debs, deb,
                                         state)
            if deb.valid:
                debs.append(deb)
            return debs
        except OSError as err:
            print(err)

    def readPackageLine(self, filename, lino, line, debs, deb, state):
        if not line.strip():
            if deb.valid:
                debs.append(copy.deepcopy(deb))
            deb.clear()
            return
        if state.inDescription or state.inContinuation:
            if line.startswith((' ', '\t')):
                if state.inDescription:
                    deb.description += line
                return
            state.inDescription = state.inContinuation = False
        key, value, ok = maybeKeyValue(line)
        if not ok:
            state.inContinuation = True
        else:
            state.inDescription = populateDeb(deb, key, value)

    def populateIndexes(self):
        commonWords = set()
        for name, deb in self.debForName.items():
            for word in normalizedWords(deb.description):
                if not bool(word):
                    continue
                if word not in commonWords:
                    self.namesForWord.setdefault(word, []).append(name)
                    if (len(self.namesForWord[word]) >
                            self.maxDebNamesForWord):
                        commonWords.add(word)
                        del self.namesForWord[word]

def maybeKeyValue(line):
    i = line.find(':')
    if i == -1:
        return None, None, False
    key = line[:i].strip()
    value = line[i + 1:].strip()
    return key, value, True

def populateDeb(deb, key, value):
    if key == 'Package':
        deb.name = value
        maybeSetKindForName(deb)
        return False
    if key == 'Version':
        deb.ver = value
        return False
    if key == 'Section':
        deb.section = value
        maybeSetKindForSection(deb)
        return False
    if key == 'Description' or key == 'Npp-Description':
        deb.description += value
        return True
    if key == 'Homepage':
        deb.url = value
        return False
    if key == 'Installed-Size':
        deb.size = int(value)
        return False
    if key == 'Tag':
        maybePopulateTags(deb, value)
        return False
    if key == 'Depends':
        maybeSetKindForDepends(deb, value)
        return False
    return False

def maybeSetKindForName(deb):
    if deb.kind is Kind.Unknown:
        if deb.name.startswith('libreoffice'):
            deb.kind = Kind.GuiApp
        elif deb.name.startswith('lib'):
            deb.kind = Kind.Library


def maybeSetKindForSection(deb):
    if deb.kind is Kind.Unknown:
        if 'Desktop' in deb.section or 'Graphical' in deb.section:
            deb.kind = Kind.GuiApp
        elif deb.section.startswith('Documentation'):
            deb.kind = Kind.Documentation
        elif deb.section.startswith('Fonts'):
            deb.kind = Kind.Font
        elif deb.section.startswith('Libraries'):
            deb.kind = Kind.Library

def maybePopulateTags(deb, tags):
    rx = re.compile(r'\s*,\s*')
    for tag in rx.split(tags):
        deb.tags.add(tag)
        maybeSetKindForTag(deb, tag)


def maybeSetKindForTag(deb, tag):
    if deb.kind is Kind.Unknown:
        if (tag.startswith('office::') or tag.startswith('uitoolkit::') or
            tag.startswith('x11::')):
            deb.kind = Kind.GuiApp
        else:
            if tag in {'interface::cli', 'interface::shell',
                       'interface::text-mode', 'interface::svga'}:
                deb.kind = Kind.ConsoleApp
            elif tag in {'interface::graphical', 'interface::x11',
                         'junior::games-gl', 'suite::gimp', 'suite::gnome',
                         'suite::kde', 'suite::netscape',
                         'suite::openoffice', 'suite::xfce'}:
                deb.kind = Kind.GuiApp
            elif tag == 'role::data':
                deb.kind = Kind.Data
            elif tag in {'role::devel-lib', 'role::plugin',
                         'role::shared-lib'}:
                deb.kind = Kind.Library
            elif tag == 'role::documentation':
                deb.kind = Kind.Documentation

def maybeSetKindForDepends(deb, depends):
    rx = re.compile(r'\blib(gtk|qt|tk|x11|fltk|motif|sdl|wx)|gnustep')
    if deb.kind is Kind.Unknown and rx.search(depends):
        deb.kind = Kind.GuiApp

def normalizedWords(line):
    nonLetterRx = re.compile(r'\P{L}+')
    stemmer = snowballstemmer.stemmer('english')
    return [word for word in stemmer.stemWords(
                     nonLetterRx.sub(' ', line).casefold().split())
            if not word.isdigit() and len(word) > 1]

if __name__ == '__main__':
    def dumpWordIndex(namesForWord):
        for word, names in namesForWord.items():
            print(word + ':', end='')
            for name in names:
                print(' ' + name, end='')
            print()

    import time
    model = Model(100)
    a = time.monotonic()
    model.readPackages()
    b = time.monotonic() - a
    print(f'read {len(model):,d} packages in {b:.02f} secs')
    c = time.monotonic()
    model.populateIndexes()
    d = time.monotonic() - c
    print(f'indexed packages in {d:.02f} secs')
    print(f'total time {b + d:.02f} secs')
    # dumpWordIndex(model.namesForWord)
