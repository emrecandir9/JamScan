import '../models/album.dart';

/// Releases used by the mock recognition and search services.
///
/// The metadata is illustrative sample data for UI work, not a Discogs
/// export. Catalogue numbers and ratings in particular are placeholders.
abstract final class MockCatalog {
  static const kindOfBlue = Album(
    id: 'mock-kind-of-blue-1959',
    title: 'Kind of Blue',
    artist: 'Miles Davis',
    year: 1959,
    format: MediaFormat.vinyl,
    formatDescription: 'Vinyl LP',
    pressingFormat: 'Vinyl, LP, Mono',
    label: 'Columbia',
    catalogNumber: 'CL 1355',
    country: 'US',
    genres: ['Jazz', 'Modal', 'Cool Jazz'],
    rating: 4.6,
    ratingCount: 1203,
    tracks: [
      Track(
        position: 'A1',
        title: 'So What',
        duration: Duration(minutes: 9, seconds: 22),
        popularityRank: 1,
      ),
      Track(
        position: 'A2',
        title: 'Freddie Freeloader',
        duration: Duration(minutes: 9, seconds: 46),
        popularityRank: 4,
      ),
      Track(
        position: 'A3',
        title: 'Blue in Green',
        duration: Duration(minutes: 5, seconds: 37),
        popularityRank: 2,
      ),
      Track(
        position: 'B1',
        title: 'All Blues',
        duration: Duration(minutes: 11, seconds: 33),
        popularityRank: 3,
      ),
      Track(
        position: 'B2',
        title: 'Flamenco Sketches',
        duration: Duration(minutes: 9, seconds: 26),
        popularityRank: 5,
      ),
    ],
  );

  static const kindOfBlueLegacy = Album(
    id: 'mock-kind-of-blue-2009',
    title: 'Kind of Blue (Legacy)',
    artist: 'Miles Davis',
    year: 2009,
    format: MediaFormat.cd,
    formatDescription: 'CD',
    pressingFormat: 'CD, Album, Reissue, Remastered',
    label: 'Columbia / Legacy',
    catalogNumber: 'SAMPLE-2009',
    country: 'Europe',
    genres: ['Jazz', 'Modal'],
    rating: 4.5,
    ratingCount: 312,
    tracks: [
      Track(
        position: '1',
        title: 'So What',
        duration: Duration(minutes: 9, seconds: 22),
        popularityRank: 1,
      ),
      Track(
        position: '2',
        title: 'Freddie Freeloader',
        duration: Duration(minutes: 9, seconds: 46),
        popularityRank: 4,
      ),
      Track(
        position: '3',
        title: 'Blue in Green',
        duration: Duration(minutes: 5, seconds: 37),
        popularityRank: 2,
      ),
      Track(
        position: '4',
        title: 'All Blues',
        duration: Duration(minutes: 11, seconds: 33),
        popularityRank: 3,
      ),
      Track(
        position: '5',
        title: 'Flamenco Sketches',
        duration: Duration(minutes: 9, seconds: 26),
        popularityRank: 5,
      ),
    ],
  );

  static const kindOfBlueReissue = Album(
    id: 'mock-kind-of-blue-1997',
    title: 'Kind of Blue',
    artist: 'Miles Davis',
    year: 1997,
    format: MediaFormat.vinyl,
    formatDescription: 'Vinyl, Reissue',
    pressingFormat: 'Vinyl, LP, Album, Reissue, 180g',
    label: 'Columbia / Legacy',
    catalogNumber: 'SAMPLE-1997',
    country: 'US',
    genres: ['Jazz', 'Modal', 'Cool Jazz'],
    rating: 4.4,
    ratingCount: 268,
    tracks: [
      Track(
        position: 'A1',
        title: 'So What',
        duration: Duration(minutes: 9, seconds: 22),
        popularityRank: 1,
      ),
      Track(
        position: 'A2',
        title: 'Freddie Freeloader',
        duration: Duration(minutes: 9, seconds: 46),
        popularityRank: 4,
      ),
      Track(
        position: 'A3',
        title: 'Blue in Green',
        duration: Duration(minutes: 5, seconds: 37),
        popularityRank: 2,
      ),
      Track(
        position: 'B1',
        title: 'All Blues',
        duration: Duration(minutes: 11, seconds: 33),
        popularityRank: 3,
      ),
      Track(
        position: 'B2',
        title: 'Flamenco Sketches',
        duration: Duration(minutes: 9, seconds: 26),
        popularityRank: 5,
      ),
    ],
  );

  static const rumours = Album(
    id: 'mock-rumours-1977',
    title: 'Rumours',
    artist: 'Fleetwood Mac',
    year: 1977,
    format: MediaFormat.vinyl,
    formatDescription: 'Vinyl LP',
    pressingFormat: 'Vinyl, LP, Album',
    label: 'Warner Bros. Records',
    catalogNumber: 'BSK 3010',
    country: 'US',
    genres: ['Rock', 'Pop Rock', 'Soft Rock'],
    rating: 4.5,
    ratingCount: 3874,
    tracks: [
      Track(
        position: 'A1',
        title: 'Second Hand News',
        duration: Duration(minutes: 2, seconds: 43),
      ),
      Track(
        position: 'A2',
        title: 'Dreams',
        duration: Duration(minutes: 4, seconds: 14),
        popularityRank: 1,
      ),
      Track(
        position: 'A3',
        title: 'Never Going Back Again',
        duration: Duration(minutes: 2, seconds: 2),
      ),
      Track(
        position: 'A4',
        title: "Don't Stop",
        duration: Duration(minutes: 3, seconds: 11),
        popularityRank: 4,
      ),
      Track(
        position: 'A5',
        title: 'Go Your Own Way',
        duration: Duration(minutes: 3, seconds: 38),
        popularityRank: 2,
      ),
      Track(
        position: 'A6',
        title: 'Songbird',
        duration: Duration(minutes: 3, seconds: 20),
        popularityRank: 5,
      ),
      Track(
        position: 'B1',
        title: 'The Chain',
        duration: Duration(minutes: 4, seconds: 28),
        popularityRank: 3,
      ),
      Track(
        position: 'B2',
        title: 'You Make Loving Fun',
        duration: Duration(minutes: 3, seconds: 31),
      ),
      Track(
        position: 'B3',
        title: "I Don't Want to Know",
        duration: Duration(minutes: 3, seconds: 11),
      ),
      Track(
        position: 'B4',
        title: 'Oh Daddy',
        duration: Duration(minutes: 3, seconds: 54),
      ),
      Track(
        position: 'B5',
        title: 'Gold Dust Woman',
        duration: Duration(minutes: 4, seconds: 51),
      ),
    ],
  );

  static const discovery = Album(
    id: 'mock-discovery-2001',
    title: 'Discovery',
    artist: 'Daft Punk',
    year: 2001,
    format: MediaFormat.vinyl,
    formatDescription: 'Vinyl 2xLP',
    pressingFormat: 'Vinyl, 2xLP, Album',
    label: 'Virgin',
    catalogNumber: 'SAMPLE-2001',
    country: 'Europe',
    genres: ['Electronic', 'House', 'Disco'],
    rating: 4.5,
    ratingCount: 2156,
    tracks: [
      Track(
        position: 'A1',
        title: 'One More Time',
        duration: Duration(minutes: 5, seconds: 20),
        popularityRank: 1,
      ),
      Track(
        position: 'A2',
        title: 'Aerodynamic',
        duration: Duration(minutes: 3, seconds: 27),
      ),
      Track(
        position: 'A3',
        title: 'Digital Love',
        duration: Duration(minutes: 4, seconds: 58),
        popularityRank: 3,
      ),
      Track(
        position: 'B1',
        title: 'Harder, Better, Faster, Stronger',
        duration: Duration(minutes: 3, seconds: 44),
        popularityRank: 2,
      ),
      Track(
        position: 'B2',
        title: 'Crescendolls',
        duration: Duration(minutes: 3, seconds: 31),
      ),
      Track(
        position: 'B3',
        title: 'Nightvision',
        duration: Duration(minutes: 1, seconds: 44),
      ),
      Track(
        position: 'B4',
        title: 'Superheroes',
        duration: Duration(minutes: 3, seconds: 57),
      ),
      Track(
        position: 'C1',
        title: 'High Life',
        duration: Duration(minutes: 3, seconds: 21),
      ),
      Track(
        position: 'C2',
        title: 'Something About Us',
        duration: Duration(minutes: 3, seconds: 51),
        popularityRank: 4,
      ),
      Track(
        position: 'C3',
        title: 'Voyager',
        duration: Duration(minutes: 3, seconds: 47),
      ),
      Track(
        position: 'C4',
        title: 'Veridis Quo',
        duration: Duration(minutes: 5, seconds: 44),
        popularityRank: 5,
      ),
      Track(
        position: 'D1',
        title: 'Short Circuit',
        duration: Duration(minutes: 3, seconds: 26),
      ),
      Track(
        position: 'D2',
        title: 'Face to Face',
        duration: Duration(minutes: 3, seconds: 58),
      ),
      Track(position: 'D3', title: 'Too Long', duration: Duration(minutes: 10)),
    ],
  );

  static const blueTrain = Album(
    id: 'mock-blue-train-1957',
    title: 'Blue Train',
    artist: 'John Coltrane',
    year: 1957,
    format: MediaFormat.vinyl,
    formatDescription: 'Vinyl LP',
    pressingFormat: 'Vinyl, LP, Album, Mono',
    label: 'Blue Note',
    catalogNumber: 'BLP 1577',
    country: 'US',
    genres: ['Jazz', 'Hard Bop'],
    rating: 4.7,
    ratingCount: 941,
    tracks: [
      Track(
        position: 'A1',
        title: 'Blue Train',
        duration: Duration(minutes: 10, seconds: 43),
        popularityRank: 1,
      ),
      Track(
        position: 'A2',
        title: "Moment's Notice",
        duration: Duration(minutes: 9, seconds: 10),
        popularityRank: 2,
      ),
      Track(
        position: 'B1',
        title: 'Locomotion',
        duration: Duration(minutes: 7, seconds: 14),
        popularityRank: 4,
      ),
      Track(
        position: 'B2',
        title: "I'm Old Fashioned",
        duration: Duration(minutes: 7, seconds: 58),
        popularityRank: 3,
      ),
      Track(
        position: 'B3',
        title: 'Lazy Bird',
        duration: Duration(minutes: 7),
        popularityRank: 5,
      ),
    ],
  );

  static const loveSupreme = Album(
    id: 'mock-a-love-supreme-1965',
    title: 'A Love Supreme',
    artist: 'John Coltrane',
    year: 1965,
    format: MediaFormat.vinyl,
    formatDescription: 'Vinyl LP',
    pressingFormat: 'Vinyl, LP, Album, Stereo',
    label: 'Impulse!',
    catalogNumber: 'A-77',
    country: 'US',
    genres: ['Jazz', 'Modal', 'Spiritual Jazz'],
    rating: 4.7,
    ratingCount: 1488,
    tracks: [
      Track(
        position: 'A1',
        title: 'Part I – Acknowledgement',
        duration: Duration(minutes: 7, seconds: 47),
        popularityRank: 1,
      ),
      Track(
        position: 'A2',
        title: 'Part II – Resolution',
        duration: Duration(minutes: 7, seconds: 22),
        popularityRank: 2,
      ),
      Track(
        position: 'B1',
        title: 'Part III – Pursuance',
        duration: Duration(minutes: 10, seconds: 42),
        popularityRank: 3,
      ),
      Track(
        position: 'B2',
        title: 'Part IV – Psalm',
        duration: Duration(minutes: 7, seconds: 5),
        popularityRank: 4,
      ),
    ],
  );

  static const moanin = Album(
    id: 'mock-moanin-1958',
    title: "Moanin'",
    artist: 'Art Blakey & The Jazz Messengers',
    year: 1958,
    format: MediaFormat.vinyl,
    formatDescription: 'Vinyl LP',
    pressingFormat: 'Vinyl, LP, Album',
    label: 'Blue Note',
    catalogNumber: 'BLP 4003',
    country: 'US',
    genres: ['Jazz', 'Hard Bop'],
    rating: 4.6,
    ratingCount: 702,
    tracks: [
      Track(
        position: 'A1',
        title: "Moanin'",
        duration: Duration(minutes: 9, seconds: 35),
        popularityRank: 1,
      ),
      Track(
        position: 'A2',
        title: 'Are You Real',
        duration: Duration(minutes: 4, seconds: 50),
        popularityRank: 3,
      ),
      Track(
        position: 'A3',
        title: 'Along Came Betty',
        duration: Duration(minutes: 6, seconds: 13),
        popularityRank: 2,
      ),
      Track(
        position: 'B1',
        title: 'The Drum Thunder Suite',
        duration: Duration(minutes: 7, seconds: 28),
        popularityRank: 5,
      ),
      Track(
        position: 'B2',
        title: 'Blues March',
        duration: Duration(minutes: 6, seconds: 15),
        popularityRank: 4,
      ),
      Track(
        position: 'B3',
        title: 'Come Rain or Come Shine',
        duration: Duration(minutes: 5, seconds: 47),
      ),
    ],
  );

  static const ledZeppelinIV = Album(
    id: 'mock-led-zeppelin-iv-1971',
    title: 'Led Zeppelin IV',
    artist: 'Led Zeppelin',
    year: 1971,
    format: MediaFormat.vinyl,
    formatDescription: 'Vinyl LP',
    pressingFormat: 'Vinyl, LP, Album',
    label: 'Atlantic',
    catalogNumber: 'SD 7208',
    country: 'US',
    genres: ['Rock', 'Hard Rock', 'Folk Rock'],
    rating: 4.6,
    ratingCount: 2731,
    tracks: [
      Track(
        position: 'A1',
        title: 'Black Dog',
        duration: Duration(minutes: 4, seconds: 55),
        popularityRank: 2,
      ),
      Track(
        position: 'A2',
        title: 'Rock and Roll',
        duration: Duration(minutes: 3, seconds: 40),
        popularityRank: 3,
      ),
      Track(
        position: 'A3',
        title: 'The Battle of Evermore',
        duration: Duration(minutes: 5, seconds: 51),
      ),
      Track(
        position: 'A4',
        title: 'Stairway to Heaven',
        duration: Duration(minutes: 8, seconds: 2),
        popularityRank: 1,
      ),
      Track(
        position: 'B1',
        title: 'Misty Mountain Hop',
        duration: Duration(minutes: 4, seconds: 38),
        popularityRank: 5,
      ),
      Track(
        position: 'B2',
        title: 'Four Sticks',
        duration: Duration(minutes: 4, seconds: 44),
      ),
      Track(
        position: 'B3',
        title: 'Going to California',
        duration: Duration(minutes: 3, seconds: 31),
      ),
      Track(
        position: 'B4',
        title: 'When the Levee Breaks',
        duration: Duration(minutes: 7, seconds: 7),
        popularityRank: 4,
      ),
    ],
  );

  /// A self-released tape with only saved metadata and no previews.
  static const liveAtTheGarage = Album(
    id: 'mock-live-at-the-garage-1994',
    title: 'Live at the Garage',
    artist: 'Unknown Artist',
    year: 1994,
    format: MediaFormat.tape,
    formatDescription: 'Cassette',
    pressingFormat: 'Cassette, Album',
    label: 'Self-released',
    catalogNumber: 'none',
    country: 'Unknown',
    genres: ['Rock'],
    isPartial: true,
    previewsAvailable: false,
    tracks: [
      Track(
        position: 'A1',
        title: 'Opening',
        duration: Duration(minutes: 6, seconds: 12),
        hasPreview: false,
      ),
      Track(
        position: 'A2',
        title: 'Second Set',
        duration: Duration(minutes: 18, seconds: 40),
        hasPreview: false,
      ),
      Track(
        position: 'B1',
        title: 'Encore',
        duration: Duration(minutes: 4, seconds: 5),
        hasPreview: false,
      ),
    ],
  );

  static const List<Album> all = [
    kindOfBlue,
    kindOfBlueLegacy,
    kindOfBlueReissue,
    rumours,
    discovery,
    blueTrain,
    loveSupreme,
    moanin,
    ledZeppelinIV,
    liveAtTheGarage,
  ];
}
