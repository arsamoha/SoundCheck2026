

clear


load SoundCheckImageData_00050.mat

figure, imagesc(imgData), axis image


%=========================================================================
% Arc Test

figure, imagesc(imgData), axis image
hold on

center = [343, -120];       % Center of the circle (x,y)

% Arc 1: Sample points
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



% Arc 2: Transducer check
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

%=========================================================================



%=========================================================================
% Arc Sampling

figure, imagesc(imgData), axis image
hold on

center = [343, -120]       % Center of the circle (x,y)

% Arc 1: Transducer check
%
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



% Arc 2: Sample points
%
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

figure
surf(ip_out'), shading interp

%=========================================================================




% Generalize calculation of Center of Rotation

% Threshold of image data
% - binary mask
thr = graythresh(imgData);
tt = imbinarize(imgData, thr);
figure, imshow(tt)
title('Binary Mask')

ee = edge(tt);
figure, imshow(ee)
title('Edge Detection')


% Find intersection of vectors along edges of the sector
% - use 'polyxpoly'


