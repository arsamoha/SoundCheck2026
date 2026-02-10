


clear



load SoundCheckImageData_00050.mat



%=========================================================================
% Arc Sampling: Center Error 1

figure, imagesc(imgData), axis image
hold on


% Shift Center closer to transducer face
%center = [343, -120];       % Center of the circle (x,y)
center = [343, -90]       % Center of the circle (x,y)



% Arc 1: transducer check
% Parameters for the arc
radius = 180;
theta1 = -pi/4 + pi/2;      % Start angle (radians)
theta2 = pi/4 + pi/2;       % End angle (radians)

% Generate 100 points
theta = linspace(theta1, theta2, 100);
x = center(1) + radius * cos(theta);
y = center(2) + radius * sin(theta);

% Plot the arc
plot(x, y, 'm-o', 'LineWidth', 1);



% Arc 2: sample points
% Parameters for the arc
radius = 250;
theta1 = -pi/4 + pi/2;      % Start angle (radians)
theta2 = pi/4 + pi/2;       % End angle (radians)

% Generate 100 points
theta = linspace(theta1, theta2, 100);
x = center(1) + radius * cos(theta);
y = center(2) + radius * sin(theta);

% Plot the arc
plot(x, y, 'r-o', 'LineWidth', 1);



arcx = x;
arcy = y;

ip_out = [];

% Sample lines
for i = 1:100
    
    ip = improfile(imgData, [center(1) arcx(i)], [center(2) arcy(i)], 200);

    ip_out(i,:) = ip';

    plot([center(1) arcx(i)], [center(2) arcy(i)], 'x:g')

end

figure
plot(ip_out')

figure, imagesc(ip_out')
title('Center Shifted toward Transducer')

figure
surf(ip_out'), shading interp

%=========================================================================



%=========================================================================
% Arc Sampling: Center Error 2

figure, imagesc(imgData), axis image
hold on


% Shift Center to Left
%center = [343, -120];       % Center of the circle (x,y)
center = [333, -120]       % Center of the circle (x,y)



% Arc 1: transducer check
% Parameters for the arc
radius = 180;
theta1 = -pi/4 + pi/2;      % Start angle (radians)
theta2 = pi/4 + pi/2;       % End angle (radians)

% Generate 100 points
theta = linspace(theta1, theta2, 100);
x = center(1) + radius * cos(theta);
y = center(2) + radius * sin(theta);

% Plot the arc
plot(x, y, 'm-o', 'LineWidth', 1);



% Arc 2: sample points
% Parameters for the arc
radius = 250;
theta1 = -pi/4 + pi/2;      % Start angle (radians)
theta2 = pi/4 + pi/2;       % End angle (radians)

% Generate 100 points
theta = linspace(theta1, theta2, 100);
x = center(1) + radius * cos(theta);
y = center(2) + radius * sin(theta);

% Plot the arc
plot(x, y, 'r-o', 'LineWidth', 1);



arcx = x;
arcy = y;

ip_out = [];

% Sample lines
for i = 1:100
    
    ip = improfile(imgData, [center(1) arcx(i)], [center(2) arcy(i)], 200);

    ip_out(i,:) = ip';

    plot([center(1) arcx(i)], [center(2) arcy(i)], 'x:g')

end

figure
plot(ip_out')

figure, imagesc(ip_out')
title('Center Shifted to Left')

figure
surf(ip_out'), shading interp
%=========================================================================


