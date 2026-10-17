const arcadeTitles = <String,String>{
  "aerofgt.zip": "Aero Fighters",
  "aof.zip": "Art of Fighting",
  "captaven.zip": "Captain America and The Avengers",
  "captcomm.zip": "Captain Commando",
  "dino.zip": "Cadillacs and Dinosaurs",
  "fatfursp.zip": "Fatal Fury Special",
  "ffight.zip": "Final Fight",
  "gijoe.zip": "G.I. Joe",
  "gunforc2.zip": "GunForce II",
  "mslug.zip": "Metal Slug",
  "mslugx.zip": "Metal Slug X",
  "mwalk.zip": "Michael Jackson's Moonwalker",
  "punisher.zip": "The Punisher",
  "robocop2.zip": "RoboCop 2",
  "sbasebal.zip": "Super Champion Baseball",
  "sf2ce.zip": "Street Fighter II: Champion Edition",
  "simpsons.zip": "The Simpsons",
  "snowbros.zip": "Snow Bros.",
  "sonicwi2.zip": "Aero Fighters 2",
  "ssriders.zip": "Sunset Riders",
  "strhoop.zip": "Street Hoop",
  "tmnt.zip": "Teenage Mutant Ninja Turtles",
  "tmnt2.zip": "Teenage Mutant Ninja Turtles: Turtles in Time",
  "toki.zip": "Toki"
};

String displayGameName(String system, String filename) {
  final arcade = arcadeTitles[filename.toLowerCase()];
  var name = arcade ?? filename.replaceFirst(RegExp(r'\.[^.]+$'),'');
  name = name.replaceAll(RegExp(r'\s*\[[^\]]*\]'),' ')
    .replaceAll(RegExp(r'\s*\([^)]*(USA|U|E|J|W|PAL|REV[^)]*)[^)]*\)'),' ')
    .replaceAll(RegExp(r'\s+'),' ').trim();
  if (system != 'Atari 2600') return name;
  final key = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'),' ').trim();
  if (key.startsWith('atari invaders') || key.startsWith('space invaders')) return 'Space Invaders';
  if (key == 'enduro' || key.startsWith('enduro ')) return 'Enduro';
  if (key == 'jungle hunt' || key.startsWith('jungle hunt ')) return 'Jungle Hunt';
  if (key == 'moon patrol' || key.startsWith('moon patrol ')) return 'Moon Patrol';
  if (key.startsWith('ms pac man') || key.startsWith('m s pac man')) return 'Ms. Pac-Man';
  if (key.startsWith('pole position') || key.startsWith('pole positition')) return 'Pole Position';
  if (key == 'river raid' || key.startsWith('river raid ')) return 'River Raid';
  return name;
}
