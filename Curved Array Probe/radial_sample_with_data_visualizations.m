clear
clc
close all

load /Users/arshad.mohammad/Desktop/SoundCheck/SoundCheck2026/Data/Image_Scans/SoundCheckImageData_00200.mat

% [filename, pathname] = uigetfile({'*.mat;*.png;*.jpg;*.jpeg;*.tif'}, ...
%                                  'Select data or image file');

% fullpath = fullfile(pathname, filename);
% 
% [~,~,ext] = fileparts(filename);
% ext = lower(ext);

% switch ext
% 
%     case '.mat'
%         data = load(fullpath);
% 
%         % Assume variable is imgData (adjust if needed)
%         if isfield(data, 'imgData')
%             imgData = data.imgData;
%         else
%             error('MAT file does not contain variable "imgData"');
%         end
% 
%     otherwise
%         img = imread(fullpath);
% 
%         % Convert to grayscale if RGB
%         if size(img,3) == 3
%             img = rgb2gray(img);
%         end
% 
%         % Convert to double
%         imgData = im2double(img);
% 
%         % Optional robustness tweaks (recommended for real images)
%         imgData = imgaussfilt(imgData, 1);   % reduce noise (esp JPG)
%         imgData = imadjust(imgData);        % improve contrast
% 
%         % Optional: flip intensity if needed
%         % imgData = imcomplement(imgData);
% end

figure, imshow(imgData, []), axis image


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

%% Generalize calculation of Center of Rotation


%% 1) Binary mask
thr = graythresh(imgData);
tt = imbinarize(imgData, thr);

figure, imshow(tt)
title('Binary Mask')

%% 2) Keep largest connected component (removes noise blobs)
cc = bwconncomp(tt);
numPixels = cellfun(@numel, cc.PixelIdxList);
[~, idx] = max(numPixels);

mask = false(size(tt));
mask(cc.PixelIdxList{idx}) = true;

%% 3) Edge detection
ee = edge(mask);

figure, imshow(ee)
title('Edge Detection')

%% 4) Detect lines using Hough transform
[H,theta,rho] = hough(ee);
peaks = houghpeaks(H,5);
lines = houghlines(ee,theta,rho,peaks);

% Filter for steep lines (sector sides)
validLines = [];

for k = 1:length(lines)
    dx = lines(k).point2(1) - lines(k).point1(1);
    dy = lines(k).point2(2) - lines(k).point1(2);
    
    angle = rad2deg(atan2(dy,dx));
    
    % Keep steep lines only
    if abs(angle) > 30 && abs(angle) < 150
        validLines = [validLines lines(k)];
    end
end

% Select two longest steep lines
lengths = arrayfun(@(L) norm(L.point1 - L.point2), validLines);
[~, order] = sort(lengths,'descend');

L1 = validLines(order(1));
L2 = validLines(order(2));

%% 5) Compute intersection (center of rotation)

x1 = L1.point1(1); y1 = L1.point1(2);
x2 = L1.point2(1); y2 = L1.point2(2);

x3 = L2.point1(1); y3 = L2.point1(2);
x4 = L2.point2(1); y4 = L2.point2(2);

den = (x1-x2)*(y3-y4) - (y1-y2)*(x3-x4);

px = ((x1*y2 - y1*x2)*(x3-x4) - (x1-x2)*(x3*y4 - y3*x4)) / den;
py = ((x1*y2 - y1*x2)*(y3-y4) - (y1-y2)*(x3*y4 - y3*x4)) / den;

%% 6) Extract boundary
B = bwboundaries(mask);
boundary = B{1};

xB = boundary(:,2);
yB = boundary(:,1);

% Keep only top arc (above center)
topMask = yB < py;

xTop = xB(topMask);
yTop = yB(topMask);

%% 7) Extend lines before intersection

xLine = linspace(1, size(imgData,2), 2000);

% Line 1
m1 = (y2 - y1)/(x2 - x1);
b1 = y1 - m1*x1;
yLine1 = m1*xLine + b1;

% Line 2
m2 = (y4 - y3)/(x4 - x3);
b2 = y3 - m2*x3;
yLine2 = m2*xLine + b2;

%% 8) Find intersections with top arc

[xi1,yi1] = polyxpoly(xLine,yLine1,xTop,yTop);
[xi2,yi2] = polyxpoly(xLine,yLine2,xTop,yTop);

%% 9) Display result

figure
imshow(imgData)
hold on

% Draw sector edges
plot(xLine,yLine1,'g','LineWidth',2)
plot(xLine,yLine2,'g','LineWidth',2)

% Plot center
plot(px,py,'ro','MarkerSize',10,'LineWidth',3)

% Plot detected corners
plot(xi1,yi1,'mo','MarkerSize',12,'LineWidth',3)
plot(xi2,yi2,'mo','MarkerSize',12,'LineWidth',3)

title('Detected Center and Top Corners')
hold off

%% Output values (optional)
center = [px py];
leftCorner = [xi1 yi1];
rightCorner = [xi2 yi2];

%% Probe Performance Bar Chart

ip_out(isnan(ip_out)) = 0;

% 1) Get mean intensity per element (each row of ip_out = one element)
colMean = mean(ip_out, 2);   % numElements x 1

numElements = length(colMean);

% 2) Find healthiest element and normalize
[bestVal, bestIdx] = max(colMean);
ratio = colMean / bestVal;   % 0 to 1 for each element

fprintf('Healthiest element: %d  (mean intensity = %.4f)\n', bestIdx, bestVal);

thresh_green  = 0.7;
thresh_yellow = 0.4;

barColors = zeros(numElements, 3);

for e = 1:numElements
    
    if ratio(e) == 0
        % No scan region — make light gray
        barColors(e,:) = [0.85 0.85 0.85];
        
    elseif ratio(e) >= thresh_green
        barColors(e,:) = [0.2 0.85 0.2];   % green
        
    elseif ratio(e) >= thresh_yellow
        barColors(e,:) = [1.0 0.75 0.0];   % yellow
        
    else
        % 0 < ratio < yellow threshold
        barColors(e,:) = [0.9 0.1 0.1];    % red
    end
end

%% Color Map of Signal Strength

figure('Color','k','Position',[100 100 1200 400])
hold on
for e = 1:numElements
    bar(e, ratio(e)*100, 1, ...
        'FaceColor', barColors(e,:), ...
        'EdgeColor', 'none')
end

yline(thresh_green*100,  '--k', 'LineWidth', 1.5, 'Label', 'Good (70%)')
yline(thresh_yellow*100, '--k', 'LineWidth', 1.5, 'Label', 'Marginal (40%)')

hold off
xlabel('Transducer Element', 'Color', 'k')
ylabel('Signal Strength (% of best element)', 'Color', 'k')
title(sprintf('Probe Element Performance  |  Reference = Element %d', bestIdx))
xlim([0 numElements+1])
ylim([0 110])
set(gca, 'Color', [0.97 0.97 0.97], 'FontSize', 11)

%% Color Strip Chart

validMask = ratio > 0;

n_good   = sum(ratio >= thresh_green & validMask);
n_yellow = sum(ratio >= thresh_yellow & ratio < thresh_green);
n_red    = sum(ratio > 0 & ratio < thresh_yellow);

n_valid = sum(validMask);

fprintf('\n--- Element Quality Summary (excluding no-scan regions) ---\n')
fprintf('Good     (>=70%%):  %d / %d = %.1f%%\n', ...
    n_good, n_valid, 100*n_good/n_valid)

fprintf('Marginal (40-70%%): %d / %d = %.1f%%\n', ...
    n_yellow, n_valid, 100*n_yellow/n_valid)

fprintf('Poor     (<40%%):   %d / %d = %.1f%%\n', ...
    n_red, n_valid, 100*n_red/n_valid)

fprintf('----------------------------------------------------------\n')

%% Color Strip (Gray for 0)

figure('Color','k','Position',[100 100 1200 120])
hold on
for e = 1:numElements
    fill([e-0.5 e+0.5 e+0.5 e-0.5], ...
         [0 0 1 1], ...
         barColors(e,:), ...
         'EdgeColor','none')
end
hold off

xlim([0 numElements+1])
ylim([0 1])
xlabel('Transducer Element')
yticks([])
title('Element Quality Color Strip')
set(gca, 'FontSize', 11)

%% Pie Chart

pct_good   = 100 * n_good   / n_valid;
pct_yellow = 100 * n_yellow / n_valid;
pct_red    = 100 * n_red    / n_valid;

figure('Color','k','Position',[300 300 600 500])
p = pie([pct_good pct_yellow pct_red]);

colorOrder = [
    0.2 0.85 0.2;   % green
    1.0 0.75 0.0;   % yellow
    0.9 0.1 0.1];   % red

patchIdx = 1;
for k = 1:length(p)
    if isa(p(k),'matlab.graphics.primitive.Patch')
        p(k).FaceColor = colorOrder(patchIdx,:);
        patchIdx = patchIdx + 1;
    end
end

legend({
    sprintf('Good (%.1f%%)', pct_good)
    sprintf('Marginal (%.1f%%)', pct_yellow)
    sprintf('Poor (%.1f%%)', pct_red)}, ...
    'Location','southoutside')

title('Probe Element Quality Distribution (Excluding No-Scan Regions)', 'Color', 'k')