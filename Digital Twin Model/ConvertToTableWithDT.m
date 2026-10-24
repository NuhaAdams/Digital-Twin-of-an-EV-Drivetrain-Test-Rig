%% ============================================================
% EXPORT MEASURED + DIGITAL TWIN DATA TO EXCEL
%
% Includes:
%   - 18 measured signals from AllData
%   - Measured RMS current
%   - Physical Pout
%   - DT speed
%   - DT torque
%   - DT phase currents
%   - DT RMS current calculated from logged phases
%   - DT RMS current DIRECTLY from Simulink (DT_Irms)
%   - DT Pout
%
% IMPORTANT:
%   DT_Irms is now the PRIMARY DT RMS current used for:
%       - Excel analysis
%       - mean current
%       - current error
%       - MAE
%       - RMSE
%       - plots
%
%   The phase-current-derived RMS value is kept only as a
%   diagnostic/check.
%
% NO ARTIFICIAL CURRENT DELAY IS APPLIED.
% ============================================================

clc;


%% ============================================================
% USER SETTINGS
% ============================================================

% Output Excel filename
filename = 'DL200V_D1.45.xlsx';


%% ============================================================
% 1. EXTRACT MEASURED DATA DIRECTLY FROM AllData
% ============================================================

if ~exist('AllData','var')

    error(['AllData does not exist in the MATLAB Workspace. ' ...
           'Run the Simulink model first.']);

end


%% ------------------------------------------------------------
% Determine AllData format
% ------------------------------------------------------------

if isa(AllData,'timeseries')

    % To Workspace -> Timeseries
    t = AllData.Time(:);
    D = squeeze(AllData.Data);


elseif isa(AllData,'Simulink.SimulationData.Signal')

    % Simulink logged signal
    t = AllData.Values.Time(:);
    D = squeeze(AllData.Values.Data);


elseif isstruct(AllData)

    % --------------------------------------------------------
    % Time
    % --------------------------------------------------------

    if isfield(AllData,'time')

        t = AllData.time(:);

    elseif isfield(AllData,'Time')

        t = AllData.Time(:);

    else

        error('Could not find time inside AllData.');

    end


    % --------------------------------------------------------
    % Data
    % --------------------------------------------------------

    if isfield(AllData,'signals')

        if isfield(AllData.signals,'values')

            D = squeeze(AllData.signals.values);

        elseif isfield(AllData.signals,'Values')

            D = squeeze(AllData.signals.Values);

        else

            error( ...
                'Could not find signal values inside AllData.signals.');

        end


    elseif isfield(AllData,'Data')

        D = squeeze(AllData.Data);

    else

        error('Could not find data inside AllData.');

    end


elseif isnumeric(AllData)

    D = squeeze(AllData);


    if exist('tout','var')

        t = tout(:);

    elseif exist('t','var')

        t = t(:);

    else

        error(['AllData is numeric, but no time vector exists. ' ...
               'Enable tout in Simulink or use Timeseries format.']);

    end


else

    error( ...
        'Unsupported AllData type: %s', ...
        class(AllData));

end


%% ============================================================
% 2. PUT MEASURED DATA INTO N x 18 FORMAT
% ============================================================

if size(D,1) == 18

    % Current form = 18 x N
    D_meas = D.';


elseif size(D,2) == 18

    % Already N x 18
    D_meas = D;


else

    fprintf('\nDetected AllData size:\n');
    disp(size(D));

    error(['Expected 18 signals inside AllData, but its dimensions ' ...
           'do not contain 18 signals.']);

end


% Ensure time is a column vector
t = t(:);


%% ------------------------------------------------------------
% Check number of samples
% ------------------------------------------------------------

if size(D_meas,1) ~= length(t)

    fprintf('\nMeasured samples = %d\n',size(D_meas,1));
    fprintf('Time samples     = %d\n',length(t));

    error( ...
        'Measured data length does not match time-vector length.');

end


fprintf('\n============================================\n');
fprintf('ALLDATA EXTRACTED SUCCESSFULLY\n');
fprintf('============================================\n');

fprintf('Samples:          %d\n',size(D_meas,1));
fprintf('Measured signals: %d\n',size(D_meas,2));
fprintf('Start time:       %.3f s\n',t(1));
fprintf('End time:         %.3f s\n',t(end));

fprintf('============================================\n\n');


%% ============================================================
% 3. MEASURED SIGNAL NAMES
% ============================================================

measuredNames = { ...
    'ActualTorque_pct', ...
    'Speed_rpm', ...
    'CommandTorque_pct', ...
    'U12_V', ...
    'U23_V', ...
    'U31_V', ...
    'V1_V', ...
    'V2_V', ...
    'V3_V', ...
    'I1_A', ...
    'I2_A', ...
    'I3_A', ...
    'ActivePower_kW', ...
    'ReactivePower_kVAr', ...
    'ApparentPower_kVA', ...
    'PowerFactor', ...
    'Frequency_Hz', ...
    'NeutralCurrent_A'};


%% ============================================================
% 4. CHECK REQUIRED EXTERNAL / DT SIGNALS EXIST
% ============================================================

requiredSignals = { ...
    'DT_Torque', ...
    'DT_Ia', ...
    'DT_Ib', ...
    'DT_Ic', ...
    'DT_Irms', ...     % <-- NEW SIMULINK RMS CURRENT
    'Pout', ...
    'DT_Pout'};


for k = 1:length(requiredSignals)

    if ~exist(requiredSignals{k},'var')

        error( ...
            'Missing Workspace variable: %s', ...
            requiredSignals{k});

    end

end


fprintf('Required DT/external signals found.\n');
fprintf('DT_Irms Workspace signal found successfully.\n');


%% ============================================================
% 5. EXTRACT DIGITAL TWIN AND POUT SIGNALS
% ============================================================

DT_Torque_data = extractToTime( ...
    DT_Torque, ...
    t, ...
    'DT_Torque');


DT_Ia_data = extractToTime( ...
    DT_Ia, ...
    t, ...
    'DT_Ia');


DT_Ib_data = extractToTime( ...
    DT_Ib, ...
    t, ...
    'DT_Ib');


DT_Ic_data = extractToTime( ...
    DT_Ic, ...
    t, ...
    'DT_Ic');


%% ------------------------------------------------------------
% NEW:
% RMS current calculated directly inside Simulink
% ------------------------------------------------------------

DT_Irms_data = extractToTime( ...
    DT_Irms, ...
    t, ...
    'DT_Irms');


%% ------------------------------------------------------------
% Physical/measured output power
% ------------------------------------------------------------

Pout_data = extractToTime( ...
    Pout, ...
    t, ...
    'Pout');


%% ------------------------------------------------------------
% Digital Twin output power
% ------------------------------------------------------------

DT_Pout_data = extractToTime( ...
    DT_Pout, ...
    t, ...
    'DT_Pout');


%% ============================================================
% 6. MEASURED RMS CURRENT
% ============================================================
%
% AllData:
%
% column 10 = I1
% column 11 = I2
% column 12 = I3
%
% Socomec phase currents are already RMS quantities.
%
% Use mean of three measured phase RMS currents.
% ============================================================

Measured_Current_RMS_A = mean( ...
    D_meas(:,10:12), ...
    2, ...
    'omitnan');


%% ============================================================
% 7. DIAGNOSTIC DT RMS CURRENT FROM LOGGED PHASES
% ============================================================
%
% This is NOT the main DT RMS current anymore.
%
% It is retained so you can compare the old calculation with
% the new DT_Irms value generated directly in Simulink.
%
% DT_Current_RMS_Calc_A =
%
% sqrt((Ia^2 + Ib^2 + Ic^2)/3)
%
% ============================================================

DT_Current_RMS_Calc_A = sqrt( ...
    (DT_Ia_data.^2 + ...
     DT_Ib_data.^2 + ...
     DT_Ic_data.^2) ./ 3);


%% ============================================================
% 8. PRIMARY DT RMS CURRENT
% ============================================================
%
% THIS is the corrected RMS current generated in Simulink:
%
%   Ia --> square --\
%   Ib --> square ---- sum --> 1/3 --> sqrt --> DT_Irms
%   Ic --> square --/
%
% Use this for ALL validation.
% ============================================================

DT_Current_RMS_A = ...
    DT_Irms_data;


%% ============================================================
% 9. FIND DIGITAL TWIN ROTOR SPEED
% ============================================================

speedVars = who('DT_Roto*');


if isempty(speedVars)

    error(['Could not find the DT rotor-speed Workspace variable. ' ...
           'Expected a variable beginning with DT_Roto...']);

end


if length(speedVars) > 1

    fprintf('\nMultiple DT rotor-speed variables found:\n');

    disp(speedVars);

    fprintf( ...
        'Using: %s\n\n', ...
        speedVars{1});

end


speedVarName = ...
    speedVars{1};


fprintf( ...
    'Using DT speed variable: %s\n', ...
    speedVarName);


DT_Speed_TS = ...
    eval(speedVarName);


DT_Speed_data = extractToTime( ...
    DT_Speed_TS, ...
    t, ...
    speedVarName);


%% ============================================================
% 10. CONVERT DT SPEED FROM rad/s TO rpm
% ============================================================
%
% Asynchronous Machine SI Units:
%
% wm = rad/s
%
% rpm = rad/s * 60/(2*pi)
%
% ============================================================

DT_Speed_rpm = ...
    DT_Speed_data ...
    .* 60/(2*pi);


%% ============================================================
% 11. FORCE ALL SIGNALS TO COLUMN VECTORS
% ============================================================

Measured_Current_RMS_A = ...
    Measured_Current_RMS_A(:);


Pout_data = ...
    Pout_data(:);


DT_Speed_rpm = ...
    DT_Speed_rpm(:);


DT_Torque_data = ...
    DT_Torque_data(:);


DT_Ia_data = ...
    DT_Ia_data(:);


DT_Ib_data = ...
    DT_Ib_data(:);


DT_Ic_data = ...
    DT_Ic_data(:);


DT_Current_RMS_Calc_A = ...
    DT_Current_RMS_Calc_A(:);


DT_Irms_data = ...
    DT_Irms_data(:);


DT_Current_RMS_A = ...
    DT_Current_RMS_A(:);


DT_Pout_data = ...
    DT_Pout_data(:);


%% ============================================================
% 12. FINAL LENGTH CHECK
% ============================================================

signalsToCheck = { ...
    Measured_Current_RMS_A, ...
    Pout_data, ...
    DT_Speed_rpm, ...
    DT_Torque_data, ...
    DT_Ia_data, ...
    DT_Ib_data, ...
    DT_Ic_data, ...
    DT_Current_RMS_Calc_A, ...
    DT_Irms_data, ...
    DT_Pout_data};


signalNamesToCheck = { ...
    'Measured_Current_RMS_A', ...
    'Pout', ...
    'DT_Speed_rpm', ...
    'DT_Torque', ...
    'DT_Ia', ...
    'DT_Ib', ...
    'DT_Ic', ...
    'DT_Current_RMS_Calc_A', ...
    'DT_Irms', ...
    'DT_Pout'};


for k = 1:length(signalsToCheck)

    if length(signalsToCheck{k}) ~= length(t)

        error( ...
            '%s has %d samples but time has %d samples.', ...
            signalNamesToCheck{k}, ...
            length(signalsToCheck{k}), ...
            length(t));

    end

end


%% ============================================================
% 13. COMBINE ALL SIGNALS
% ============================================================
%
% Keep both:
%
% DT_Current_RMS_Calc_A
%   = RMS calculated afterwards from exported phase currents
%
% DT_Irms_A
%   = corrected RMS calculated directly inside Simulink
%
% ============================================================

AllCombined = [ ...
    D_meas, ...
    Measured_Current_RMS_A, ...
    Pout_data, ...
    DT_Speed_rpm, ...
    DT_Torque_data, ...
    DT_Ia_data, ...
    DT_Ib_data, ...
    DT_Ic_data, ...
    DT_Current_RMS_Calc_A, ...
    DT_Irms_data, ...
    DT_Pout_data];


%% ============================================================
% 14. COMPLETE COLUMN NAMES
% ============================================================

allNames = { ...
    'ActualTorque_pct', ...
    'Speed_rpm', ...
    'CommandTorque_pct', ...
    'U12_V', ...
    'U23_V', ...
    'U31_V', ...
    'V1_V', ...
    'V2_V', ...
    'V3_V', ...
    'I1_A', ...
    'I2_A', ...
    'I3_A', ...
    'ActivePower_kW', ...
    'ReactivePower_kVAr', ...
    'ApparentPower_kVA', ...
    'PowerFactor', ...
    'Frequency_Hz', ...
    'NeutralCurrent_A', ...
    'Measured_Current_RMS_A', ...
    'Pout_W', ...
    'DT_Speed_rpm', ...
    'DT_Torque_Nm', ...
    'DT_Ia_A', ...
    'DT_Ib_A', ...
    'DT_Ic_A', ...
    'DT_Current_RMS_Calc_A', ...
    'DT_Irms_A', ...
    'DT_Pout_W'};


%% ============================================================
% 15. CREATE MATLAB TABLE
% ============================================================

ResultsTable = array2table( ...
    AllCombined, ...
    'VariableNames', ...
    allNames);


% Add time as first column
ResultsTable = addvars( ...
    ResultsTable, ...
    t, ...
    'Before', ...
    1, ...
    'NewVariableNames', ...
    'Time_s');


%% ============================================================
% 16. EXPORT TO EXCEL
% ============================================================

writetable( ...
    ResultsTable, ...
    filename);


%% ============================================================
% 17. COMPARISON REGION
% ============================================================
%
% Ignore first second because of startup transient.
%
% NOTE:
% For your final steady-state loaded analysis you are already
% selecting the final 2 s of each torque plateau separately.
%
% This section is only a quick overall check of this test file.
% ============================================================

steadyMask = ...
    t >= 1;


%% ============================================================
% 18. CURRENT COMPARISON
% ============================================================
%
% IMPORTANT:
%
% This now uses DT_Irms from Simulink, NOT the offline phase
% current calculation.
% ============================================================

MeasuredMeanCurrent = mean( ...
    Measured_Current_RMS_A(steadyMask), ...
    'omitnan');


DTMeanCurrent = mean( ...
    DT_Irms_data(steadyMask), ...
    'omitnan');


CurrentError_A = ...
    DTMeanCurrent ...
    - MeasuredMeanCurrent;


if abs(MeasuredMeanCurrent) > eps

    CurrentError_pct = ...
        (CurrentError_A ...
        / MeasuredMeanCurrent) ...
        * 100;

else

    CurrentError_pct = NaN;

end


%% ------------------------------------------------------------
% Current MAE
% ------------------------------------------------------------

validCurrent = ...
    steadyMask & ...
    isfinite(Measured_Current_RMS_A) & ...
    isfinite(DT_Irms_data);


CurrentMAE_A = mean( ...
    abs( ...
    DT_Irms_data(validCurrent) ...
    - Measured_Current_RMS_A(validCurrent)), ...
    'omitnan');


%% ------------------------------------------------------------
% Current RMSE
% ------------------------------------------------------------

CurrentRMSE_A = sqrt( ...
    mean( ...
    (DT_Irms_data(validCurrent) ...
    - Measured_Current_RMS_A(validCurrent)).^2, ...
    'omitnan'));


%% ============================================================
% 19. RMS CALCULATION CROSS-CHECK
% ============================================================
%
% Compare:
%
% 1. Old/offline RMS:
%    DT_Current_RMS_Calc_A
%
% 2. New Simulink RMS:
%    DT_Irms_data
%
% This is useful to verify the corrected Simulink block.
% ============================================================

MeanOldDTCurrent = mean( ...
    DT_Current_RMS_Calc_A(steadyMask), ...
    'omitnan');


MeanNewDTCurrent = mean( ...
    DT_Irms_data(steadyMask), ...
    'omitnan');


RMSMethodDifference_A = ...
    MeanNewDTCurrent ...
    - MeanOldDTCurrent;


%% ============================================================
% 20. SPEED COMPARISON
% ============================================================

MeasuredMeanSpeed = mean( ...
    D_meas(steadyMask,2), ...
    'omitnan');


DTMeanSpeed = mean( ...
    DT_Speed_rpm(steadyMask), ...
    'omitnan');


SpeedError_rpm = ...
    DTMeanSpeed ...
    - MeasuredMeanSpeed;


if abs(MeasuredMeanSpeed) > eps

    SpeedError_pct = ...
        (SpeedError_rpm ...
        / MeasuredMeanSpeed) ...
        * 100;

else

    SpeedError_pct = NaN;

end


%% ------------------------------------------------------------
% Speed MAE
% ------------------------------------------------------------

validSpeed = ...
    steadyMask & ...
    isfinite(D_meas(:,2)) & ...
    isfinite(DT_Speed_rpm);


SpeedMAE_rpm = mean( ...
    abs( ...
    DT_Speed_rpm(validSpeed) ...
    - D_meas(validSpeed,2)), ...
    'omitnan');


%% ------------------------------------------------------------
% Speed RMSE
% ------------------------------------------------------------

SpeedRMSE_rpm = sqrt( ...
    mean( ...
    (DT_Speed_rpm(validSpeed) ...
    - D_meas(validSpeed,2)).^2, ...
    'omitnan'));


%% ============================================================
% 21. OUTPUT POWER COMPARISON
% ============================================================

MeasuredMeanPout = mean( ...
    Pout_data(steadyMask), ...
    'omitnan');


DTMeanPout = mean( ...
    DT_Pout_data(steadyMask), ...
    'omitnan');


PoutError_W = ...
    DTMeanPout ...
    - MeasuredMeanPout;


if abs(MeasuredMeanPout) > eps

    PoutError_pct = ...
        (PoutError_W ...
        / MeasuredMeanPout) ...
        * 100;

else

    PoutError_pct = NaN;

end


%% ------------------------------------------------------------
% Pout MAE
% ------------------------------------------------------------

validPout = ...
    steadyMask & ...
    isfinite(Pout_data) & ...
    isfinite(DT_Pout_data);


PoutMAE_W = mean( ...
    abs( ...
    DT_Pout_data(validPout) ...
    - Pout_data(validPout)), ...
    'omitnan');


%% ------------------------------------------------------------
% Pout RMSE
% ------------------------------------------------------------

PoutRMSE_W = sqrt( ...
    mean( ...
    (DT_Pout_data(validPout) ...
    - Pout_data(validPout)).^2, ...
    'omitnan'));


%% ============================================================
% 22. DISPLAY RESULTS
% ============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf('EXCEL EXPORT COMPLETE\n');
fprintf('====================================================\n');

fprintf('File: %s\n',filename);

fprintf('Rows:    %d\n',height(ResultsTable));
fprintf('Columns: %d\n',width(ResultsTable));

fprintf('Start time: %.3f s\n',t(1));
fprintf('End time:   %.3f s\n',t(end));


%% ------------------------------------------------------------
% Current
% ------------------------------------------------------------

fprintf('\n');
fprintf('CURRENT COMPARISON USING NEW SIMULINK DT_Irms\n');
fprintf('----------------------------------------------------\n');

fprintf( ...
    'Measured RMS current:     %.4f A\n', ...
    MeasuredMeanCurrent);

fprintf( ...
    'DT_Irms current:          %.4f A\n', ...
    DTMeanCurrent);

fprintf( ...
    'Current difference:       %+.4f A\n', ...
    CurrentError_A);

fprintf( ...
    'Current error:            %+.2f %%\n', ...
    CurrentError_pct);

fprintf( ...
    'Current MAE:              %.4f A\n', ...
    CurrentMAE_A);

fprintf( ...
    'Current RMSE:             %.4f A\n', ...
    CurrentRMSE_A);


%% ------------------------------------------------------------
% RMS-method check
% ------------------------------------------------------------

fprintf('\n');
fprintf('DT RMS CALCULATION CHECK\n');
fprintf('----------------------------------------------------\n');

fprintf( ...
    'Old phase-derived RMS:    %.4f A\n', ...
    MeanOldDTCurrent);

fprintf( ...
    'New Simulink DT_Irms:     %.4f A\n', ...
    MeanNewDTCurrent);

fprintf( ...
    'Difference:               %+.4f A\n', ...
    RMSMethodDifference_A);


%% ------------------------------------------------------------
% Speed
% ------------------------------------------------------------

fprintf('\n');
fprintf('SPEED COMPARISON\n');
fprintf('----------------------------------------------------\n');

fprintf( ...
    'Measured speed:           %.2f rpm\n', ...
    MeasuredMeanSpeed);

fprintf( ...
    'DT speed:                 %.2f rpm\n', ...
    DTMeanSpeed);

fprintf( ...
    'Speed difference:         %+.2f rpm\n', ...
    SpeedError_rpm);

fprintf( ...
    'Speed error:              %+.2f %%\n', ...
    SpeedError_pct);

fprintf( ...
    'Speed MAE:                %.2f rpm\n', ...
    SpeedMAE_rpm);

fprintf( ...
    'Speed RMSE:               %.2f rpm\n', ...
    SpeedRMSE_rpm);


%% ------------------------------------------------------------
% Output power
% ------------------------------------------------------------

fprintf('\n');
fprintf('OUTPUT POWER COMPARISON\n');
fprintf('----------------------------------------------------\n');

fprintf( ...
    'Measured Pout:            %.4f W\n', ...
    MeasuredMeanPout);

fprintf( ...
    'DT Pout:                  %.4f W\n', ...
    DTMeanPout);

fprintf( ...
    'Pout difference:          %+.4f W\n', ...
    PoutError_W);

fprintf( ...
    'Pout error:               %+.2f %%\n', ...
    PoutError_pct);

fprintf( ...
    'Pout MAE:                 %.4f W\n', ...
    PoutMAE_W);

fprintf( ...
    'Pout RMSE:                %.4f W\n', ...
    PoutRMSE_W);

fprintf('====================================================\n\n');


%% ============================================================
% 23. DISPLAY FIRST 10 ROWS
% ============================================================

disp( ...
    ResultsTable( ...
    1:min(10,height(ResultsTable)), ...
    :));


%% ============================================================
% 24. PLOT RMS CURRENT
%
% PRIMARY comparison:
%
% Measured RMS vs new Simulink DT_Irms
% ============================================================

figure;

plot( ...
    t, ...
    Measured_Current_RMS_A, ...
    'LineWidth',1.5);

hold on;


plot( ...
    t, ...
    DT_Irms_data, ...
    'LineWidth',1.5);


grid on;
box on;

xlabel('Time (s)');
ylabel('Current (A RMS)');

title('Measured vs Digital Twin RMS Current');

legend( ...
    'Measured RMS Current', ...
    'DT RMS Current (Simulink)', ...
    'Location','best');


%% ============================================================
% 25. PLOT BOTH DT RMS METHODS
%
% Diagnostic only.
% ============================================================

figure;

plot( ...
    t, ...
    DT_Current_RMS_Calc_A, ...
    'LineWidth',1.2);

hold on;


plot( ...
    t, ...
    DT_Irms_data, ...
    'LineWidth',1.5);


grid on;
box on;

xlabel('Time (s)');
ylabel('DT RMS Current (A)');

title('Digital Twin RMS Current Calculation Comparison');

legend( ...
    'Calculated from Logged Ia, Ib, Ic', ...
    'Calculated Directly in Simulink', ...
    'Location','best');


%% ============================================================
% 26. PLOT SPEED
% ============================================================

figure;

plot( ...
    t, ...
    D_meas(:,2), ...
    'LineWidth',1.5);

hold on;


plot( ...
    t, ...
    DT_Speed_rpm, ...
    'LineWidth',1.5);


grid on;
box on;

xlabel('Time (s)');
ylabel('Speed (rpm)');

title('Measured vs Digital Twin Speed');

legend( ...
    'Measured Speed', ...
    'DT Speed', ...
    'Location','best');


%% ============================================================
% 27. PLOT OUTPUT POWER
% ============================================================

figure;

plot( ...
    t, ...
    Pout_data, ...
    'LineWidth',1.5);

hold on;


plot( ...
    t, ...
    DT_Pout_data, ...
    'LineWidth',1.5);


grid on;
box on;

xlabel('Time (s)');
ylabel('Output Power (W)');

title('Measured vs Digital Twin Output Power');

legend( ...
    'Measured Pout', ...
    'DT Pout', ...
    'Location','best');


%% ============================================================
% LOCAL FUNCTION
% EXTRACT ANY WORKSPACE SIGNAL AND ALIGN IT TO t
% ============================================================

function y = extractToTime(x,t,varName)


    %% --------------------------------------------------------
    % TIMESERIES
    % ---------------------------------------------------------

    if isa(x,'timeseries')

        tx = x.Time(:);

        yx = squeeze(x.Data);


    %% --------------------------------------------------------
    % SIMULINK LOGGED SIGNAL
    % ---------------------------------------------------------

    elseif isa(x,'Simulink.SimulationData.Signal')

        tx = x.Values.Time(:);

        yx = squeeze(x.Values.Data);


    %% --------------------------------------------------------
    % STRUCTURE
    % ---------------------------------------------------------

    elseif isstruct(x)


        % ----------------------------------------------------
        % Time
        % -----------------------------------------------------

        if isfield(x,'time')

            tx = x.time(:);

        elseif isfield(x,'Time')

            tx = x.Time(:);

        else

            error( ...
                'Could not find time information for %s.', ...
                varName);

        end


        % ----------------------------------------------------
        % Data
        % -----------------------------------------------------

        if isfield(x,'signals')

            if isfield(x.signals,'values')

                yx = ...
                    squeeze(x.signals.values);

            elseif isfield(x.signals,'Values')

                yx = ...
                    squeeze(x.signals.Values);

            else

                error( ...
                    'Could not find signal data for %s.', ...
                    varName);

            end


        elseif isfield(x,'Data')

            yx = ...
                squeeze(x.Data);

        else

            error( ...
                'Could not find signal data for %s.', ...
                varName);

        end


    %% --------------------------------------------------------
    % NUMERIC VECTOR
    % ---------------------------------------------------------

    elseif isnumeric(x)

        yx = squeeze(x);


        if numel(yx) == numel(t)

            y = yx(:);

            return;

        else

            error( ...
                ['%s is numeric but has %d samples, while ' ...
                 'AllData has %d samples.'], ...
                varName, ...
                numel(yx), ...
                numel(t));

        end


    else

        error( ...
            'Unsupported type for %s: %s', ...
            varName, ...
            class(x));

    end


    %% --------------------------------------------------------
    % MAKE DATA A COLUMN
    % ---------------------------------------------------------

    yx = yx(:);


    if length(tx) ~= length(yx)

        error( ...
            ['Time and data lengths do not match for %s. ' ...
             'Time = %d, Data = %d.'], ...
            varName, ...
            length(tx), ...
            length(yx));

    end


    %% --------------------------------------------------------
    % REMOVE INVALID VALUES
    % ---------------------------------------------------------

    valid = ...
        isfinite(tx) & ...
        isfinite(yx);


    tx = ...
        tx(valid);


    yx = ...
        yx(valid);


    if isempty(tx)

        error( ...
            'No valid samples found for %s.', ...
            varName);

    end


    %% --------------------------------------------------------
    % REMOVE DUPLICATE TIMESTAMPS
    % ---------------------------------------------------------

    [tx,uniqueIdx] = ...
        unique(tx,'stable');


    yx = ...
        yx(uniqueIdx);


    %% --------------------------------------------------------
    % MATCH SIGNAL TO AllData TIME
    % ---------------------------------------------------------

    if length(tx) == 1

        % Constant signal
        y = ...
            repmat( ...
            yx(1), ...
            length(t), ...
            1);

    else

        y = interp1( ...
            tx, ...
            yx, ...
            t, ...
            'linear', ...
            'extrap');

    end


    y = y(:);

end