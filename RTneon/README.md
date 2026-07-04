# Rutneon
A Proccessor made by Me :3
this is the emulator directory for it.

Rutneon is a 12h10bit* Proccessor with 6 Eon Units (TUs) 
Execution binaries should be formatted in VX48. Padding Required.


* 12 hybrid 10 bit; 12 bit instruction length, 10 bit data length


If you want to compile this you need to link it to raylib. 
this is the build arguments i used (in the main directory):

zig build-exe RTneon.zig -LAssets -lraylib -lc
