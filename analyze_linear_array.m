
clear; close all; clc;

%% Paths
dataDir = '/Users/trisha/Projects/SoundCheck/Verasonics_Testing/LinearArrayImages/unlabled/';  % test directory with .mat
outputDir = '/Users/trisha/Projects/SoundCheck/Linear_Analysis/';  % results saved here

%% Params
threshold = 0.70;  % min acceptable brightness (set to 70% of max)

%% Get all .mat files in the directory
matFiles = dir(fullfile(dataDir, '*.mat'));
numFiles = length(matFiles);

%% Init
allColumnScores = [];
allPercentPerformance = [];
fileNames = {};
allPercentPerRow = {};
dropoutsAll = cell(1, numFiles);

%% Main analysis loop
for fileIdx = 1:numFiles
    fileName = matFiles(fileIdx).name;
    filePath = fullfile(dataDir, fileName);
    fileNames{fileIdx} = fileName;
    
    fprintf('\n[%d/%d] Processing: %s\n', fileIdx, numFiles, fileName);
    
    try
        % Load img data
        data = load(filePath);
        
        % Extract imgData
        if isfield(data, 'imgData')
            imgData = data.imgData;
        elseif isfield(data, 'imageData')
            imgData = data.imageData;
        else
            % Try to find img data automatically
            fields = fieldnames(data);
            imgData = data.(fields{1});
            warning('Using field %s as image data', fields{1});
        end
        
        % Get img dimensions
        [numRows, numCols] = size(imgData);
        
        %% Compute column-wise brightness scores (TODO: choose one)
        columnScore = mean(imgData, 1);   
        % columnScore = median(imgData, 1);     
        % columnScore = max(imgData, [], 1);       

        %% Determine ref (max) brightness
        refBrightness = max(columnScore);
        fprintf('  Reference brightness: %.2f \n', refBrightness);
        
        %% Calculate percent performance
        percentPerformance = (columnScore / refBrightness) * 100;
        percentPerRow = (double(imgData) ./ refBrightness) * 100; % percent performance per row for each column

        % Store results
        allColumnScores(fileIdx, :) = columnScore;
        allPercentPerformance(fileIdx, :) = percentPerformance;
        allPercentPerRow{fileIdx} = percentPerRow;

        %% ID dropout regions
        dropouts = find(percentPerformance < (threshold * 100));
        dropoutsAll{fileIdx} = dropouts; 
        if ~isempty(dropouts)
            fprintf('  WARNING: %d columns below %.0f%% threshold\n', ...
                numel(dropouts), threshold * 100);
            fprintf('  Column percent performance (for columns with dropout):\n');
            for k = 1:numel(dropouts)
                c = dropouts(k);
                fprintf('    Col %d : %.1f%%\n', c, percentPerformance(c));
            end
        else
            fprintf('  All columns above threshold\n');
        end
    end
end

%% Save numerical results
resultsFile = fullfile(outputDir, 'analysis_results.mat');
save(resultsFile, 'allColumnScores', 'allPercentPerformance', 'allPercentPerRow', 'fileNames', 'threshold');
fprintf('Saved: analysis_results.mat\n');
fprintf('Results saved to: %s\n', outputDir);

% Summary
fprintf('\nSummary of files with columns below %.0f%% threshold:\n', threshold*100);
anyProblems = false;
totalCols = size(allPercentPerformance, 2); % total columns (assumes consistent #cols across files)
for f = 1:numFiles
    cols = dropoutsAll{f};
    if ~isempty(cols)
        anyProblems = true;
        fprintf('  %s : %d/%d columns below threshold -> cols: ', ...
                fileNames{f}, numel(cols), totalCols);
        fprintf('%d ', cols);
        fprintf('\n');
    end
end
if ~anyProblems
    fprintf('  No files with columns below threshold\n');
end