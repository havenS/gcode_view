(Clamp 20mm)
(T1 D=6 CR=0 - ZMIN=-15 - flat end mill)
G90
G94
G17
G21

G28 G91 Z0
G90

(Clamp contour)
T1
S18000 M3
G54
G0 X0 Y0 Z15
G0 X114.655 Y41.819 Z15
G0 Z5
G1 Z-15 F500
G1 X120 Y40 F800
G1 X130 Y50
G1 X130 Y70
G1 X120 Y80
G1 X80 Y80
G1 X70 Y70
G1 X70 Y50
G1 X80 Y40
G1 X114.655 Y41.819
G0 Z15
G0 X0 Y0 Z15

G28 G91 Z0
G90
G28 G91 X0 Y0
G90
M5
M30 