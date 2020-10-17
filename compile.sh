rm *.o
rm *.nes
rm *.dbg

echo ""
echo Compiling...
/var/www/html/cc65/bin/ca65 game.asm -g -o tne-nes-game.o -t nes
echo Linking...
/var/www/html/cc65/bin/ld65 -o tno-nes-game.nes -t nes --dbgfile tne-nes-game.nes.dbg tne-nes-game.o
echo Success!

