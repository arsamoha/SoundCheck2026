clear
clc
close all

% load Data/Test_Images/SC2026test01Stills0001.png

img = im2double(imread('Data/Test_Images/SC2026test01Stills0001.png'));

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

%% Bar Chart

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