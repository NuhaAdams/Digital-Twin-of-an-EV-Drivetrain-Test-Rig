%VEHICLE DYNAMICS PARAMETERS
M=1600; %mass of the vehicle(kg)
g=9.81; %acceleration due to gravity (m/s^2)
alpha=0; %road angle (degree)
rrc=0.01; %Rolling resistance Coefficient
Af=2.3; %vehicle frontal area (m^2)
Cd=0.3; %Drag Coefficient,
rho = 1.23; %Density of Air (kg/m^3)
Lambda= 1.05; %Rotational Inertia Coefficient
r=0.339; %Radius of Wheel (m) (225/55R17)
%V=80; %velocity of vehicle (km/hr)
%acc=0.0345; % acceleration of vehicle(m/s^2)
Gr=1; %Gear ratio
Vdc=380
Ts= 0.0002
Kt=0.44
driveCycle = [
    0    0
    5    -15
    10   -30
    15   -30
    20   -30
    25   -15
    30   0
];