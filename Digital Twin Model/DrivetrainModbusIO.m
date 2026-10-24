classdef DrivetrainModbusIO < matlab.System

    % ================================================================
    % DRIVETRAIN MODBUS I/O
    %
    % Delta ASDA-A3:
    %   Slave ID = 6
    %
    % Socomec:
    %   Slave ID = 3
    %
    % Serial:
    %   COM7
    %   38400 baud
    %   8-N-2
    %
    % Sample rate:
    %   Ts = 0.1 s = 10 Hz
    % ================================================================


    properties (Nontunable)

        %% RS-485
        Port = 'COM7'
        BaudRate = 38400

        % KEEP AT 0.1 s = 10 Hz
        SampleTime = 0.1

        % Reliable gap between Modbus transactions
        InterTransactionDelay = 0.015

        % Delay before retry
        RetryDelay = 0.05

        % Servo communication attempts
        MaxModbusAttempts = 3


        %% SAFETY LIMITS
        MaxTorque_pct = 50
        MaxSpeed_rpm = 2800


        %% MODBUS SLAVE IDs
        ServoID = 6
        PowerMeterID = 3

    end


    properties (Access = private)

        % Modbus connection
        m

        % Previous speed-limit command
        lastSpeedLimitRaw = uint32(4294967295)

        % Previous torque command
        lastTorqueCommand_pct = NaN

        % Servo enable flag
        servoEnabled = false

        % Last valid Socomec data
        %
        % [VLL(3);
        %  VLN(3);
        %  I(3);
        %  P;
        %  Q;
        %  S;
        %  PF;
        %  F;
        %  In]
        lastMeterValues

        % Prevent repeated warning messages
        meterWarningIssued = false

    end


    methods (Access = protected)

        %% ============================================================
        % VALIDATE PROPERTIES
        % ============================================================
        function validatePropertiesImpl(obj)

            validateattributes(obj.SampleTime, ...
                {'numeric'}, ...
                {'scalar','real','finite','positive'});

            validateattributes(obj.InterTransactionDelay, ...
                {'numeric'}, ...
                {'scalar','real','finite','>=',0.005});

            validateattributes(obj.RetryDelay, ...
                {'numeric'}, ...
                {'scalar','real','finite','positive'});

            validateattributes(obj.MaxModbusAttempts, ...
                {'numeric'}, ...
                {'scalar','integer','>=',1});

            validateattributes(obj.MaxTorque_pct, ...
                {'numeric'}, ...
                {'scalar','real','finite','positive','<=',500});

            validateattributes(obj.MaxSpeed_rpm, ...
                {'numeric'}, ...
                {'scalar','real','finite','positive','<=',7500});

        end


        %% ============================================================
        % VALIDATE INPUTS
        % ============================================================
        function validateInputsImpl(~, ...
                torqueCommand_pct, ...
                speedLimit_rpm)

            validateattributes(torqueCommand_pct, ...
                {'double'}, ...
                {'scalar','real'});

            validateattributes(speedLimit_rpm, ...
                {'double'}, ...
                {'scalar','real'});

        end


        %% ============================================================
        % SETUP
        % ============================================================
        function setupImpl(obj)

            %% --------------------------------------------------------
            % OPEN MODBUS CONNECTION
            % ---------------------------------------------------------

            obj.m = modbus( ...
                'serialrtu', ...
                obj.Port, ...
                'BaudRate', obj.BaudRate, ...
                'DataBits', 8, ...
                'Parity', 'none', ...
                'StopBits', 2, ...
                'Timeout', 0.5);

            obj.m.ByteOrder = 'big-endian';
            obj.m.WordOrder = 'big-endian';

            % Allow USB-RS485 interface and slaves to settle
            pause(0.5);


            %% --------------------------------------------------------
            % RESET INTERNAL STATES
            % ---------------------------------------------------------

            obj.lastSpeedLimitRaw = uint32(4294967295);

            obj.lastTorqueCommand_pct = NaN;

            obj.servoEnabled = false;


            % Safe initial Socomec values.
            %
            % Prevent NaN / Inf entering Digital Twin at t = 0.
            obj.lastMeterValues = zeros(15,1);

            % Safe frequency fallback
            obj.lastMeterValues(14) = 50;

            obj.meterWarningIssued = false;


            %% --------------------------------------------------------
            % P2.030 = 5
            %
            % Communication mode
            % ---------------------------------------------------------

            writeRegisters(obj, ...
                'holdingregs', ...
                573, ...
                5, ...
                obj.ServoID, ...
                'int16');


            %% --------------------------------------------------------
            % P3.006 = 001FH
            %
            % Software control DI1-DI5
            % ---------------------------------------------------------

            writeRegisters(obj, ...
                'holdingregs', ...
                781, ...
                hex2dec('001F'), ...
                obj.ServoID, ...
                'uint16');


            %% --------------------------------------------------------
            % P4.007 = 0000H
            %
            % Start software DIs OFF
            % ---------------------------------------------------------

            writeRegisters(obj, ...
                'holdingregs', ...
                1039, ...
                hex2dec('0000'), ...
                obj.ServoID, ...
                'uint16');


            %% --------------------------------------------------------
            % P1.001 = 0003H
            %
            % Torque control mode
            % ---------------------------------------------------------

            writeRegisters(obj, ...
                'holdingregs', ...
                259, ...
                hex2dec('0003'), ...
                obj.ServoID, ...
                'uint16');


            %% --------------------------------------------------------
            % P1.002 = 0001H
            %
            % Enable speed limit in torque mode
            % ---------------------------------------------------------

            writeRegisters(obj, ...
                'holdingregs', ...
                261, ...
                hex2dec('0001'), ...
                obj.ServoID, ...
                'uint16');


            %% --------------------------------------------------------
            % P1.012 = 0 %
            %
            % Safe initial torque command
            % ---------------------------------------------------------

            writeRegisters(obj, ...
                'holdingregs', ...
                281, ...
                0, ...
                obj.ServoID, ...
                'int16');

            obj.lastTorqueCommand_pct = 0;


            %% ========================================================
            % DIGITAL INPUT ASSIGNMENTS
            %
            % DI1 = SON
            % DI2 = SPD1
            % DI3 = TCM0
            % DI4 = TCM1
            % DI5 = SPD0
            %
            % TCM1 TCM0 = 0 1
            %      -> P1.012 torque command
            %
            % SPD1 SPD0 = 0 1
            %      -> P1.009 speed limit
            % ========================================================


            %% DI1 = SON
            writeRegisters(obj, ...
                'holdingregs', ...
                533, ...
                hex2dec('0101'), ...
                obj.ServoID, ...
                'uint16');


            %% DI2 = SPD1
            writeRegisters(obj, ...
                'holdingregs', ...
                535, ...
                hex2dec('0115'), ...
                obj.ServoID, ...
                'uint16');


            %% DI3 = TCM0
            writeRegisters(obj, ...
                'holdingregs', ...
                537, ...
                hex2dec('0116'), ...
                obj.ServoID, ...
                'uint16');


            %% DI4 = TCM1
            writeRegisters(obj, ...
                'holdingregs', ...
                539, ...
                hex2dec('0117'), ...
                obj.ServoID, ...
                'uint16');


            %% DI5 = SPD0
            writeRegisters(obj, ...
                'holdingregs', ...
                541, ...
                hex2dec('0114'), ...
                obj.ServoID, ...
                'uint16');


            %% --------------------------------------------------------
            % P0.017 = 51
            %
            % Monitor 1 = actual motor speed
            % ---------------------------------------------------------

            writeRegisters(obj, ...
                'holdingregs', ...
                35, ...
                51, ...
                obj.ServoID, ...
                'uint16');


            %% --------------------------------------------------------
            % P0.018 = 54
            %
            % Monitor 2 = actual motor torque
            % ---------------------------------------------------------

            writeRegisters(obj, ...
                'holdingregs', ...
                37, ...
                54, ...
                obj.ServoID, ...
                'uint16');


            %% ========================================================
            % VERIFY DRIVE CONFIGURATION
            % ========================================================

            %% --------------------------------------------------------
            % Verify torque mode
            % --------------------------------------------------------

            modeValue = readRegisters(obj, ...
                'holdingregs', ...
                259, ...
                1, ...
                obj.ServoID, ...
                'uint16');


            controlMode = bitand( ...
                uint16(modeValue(1)), ...
                uint16(255));


            if controlMode ~= 3

                error( ...
                    'DrivetrainModbusIO:ControlMode', ...
                    'P1.001 is not set to torque mode.');

            end


            %% --------------------------------------------------------
            % Verify speed limit enabled
            % --------------------------------------------------------

            speedLimitConfig = readRegisters(obj, ...
                'holdingregs', ...
                261, ...
                1, ...
                obj.ServoID, ...
                'uint16');


            if bitand( ...
                    uint16(speedLimitConfig(1)), ...
                    uint16(1)) == 0

                error( ...
                    'DrivetrainModbusIO:SpeedLimitDisabled', ...
                    'P1.002 speed-limit function is not enabled.');

            end


            %% --------------------------------------------------------
            % Verify software DI control
            % --------------------------------------------------------

            diControl = readRegisters(obj, ...
                'holdingregs', ...
                781, ...
                1, ...
                obj.ServoID, ...
                'uint16');


            if bitand( ...
                    uint16(diControl(1)), ...
                    uint16(31)) ~= uint16(31)

                error( ...
                    'DrivetrainModbusIO:DIControl', ...
                    'P3.006 must enable software DI1-DI5.');

            end


            %% --------------------------------------------------------
            % Verify torque resolution
            %
            % P2.112 bit 14 = 0
            % --------------------------------------------------------

            torqueConfig = readRegisters(obj, ...
                'holdingregs', ...
                737, ...
                1, ...
                obj.ServoID, ...
                'uint16');


            if bitget(uint16(torqueConfig(1)),15) ~= 0

                error( ...
                    'DrivetrainModbusIO:TorqueResolution', ...
                    'Clear P2.112 bit 14 for 1 percent torque units.');

            end


            %% --------------------------------------------------------
            % ENABLE SERVO
            %
            % P4.007 = 0015H
            %
            % DI1 = SON
            % DI3 = TCM0
            % DI5 = SPD0
            %
            % Readback may show 0215.
            % ---------------------------------------------------------

            writeRegisters(obj, ...
                'holdingregs', ...
                1039, ...
                hex2dec('0015'), ...
                obj.ServoID, ...
                'uint16');


            obj.servoEnabled = true;

            pause(0.1);

        end


        %% ============================================================
        % STEP
        %
        % Ts = 0.1 s = 10 Hz
        % ============================================================
        function [actualTorque_pct, ...
                  speed_rpm, ...
                  command_pct, ...
                  VLL_V, ...
                  VLN_V, ...
                  I_A, ...
                  ActivePower_kW, ...
                  ReactivePower_kVAr, ...
                  ApparentPower_kVA, ...
                  PowerFactor, ...
                  Frequency_Hz, ...
                  NeutralCurrent_A, ...
                  AllData] = stepImpl(obj, ...
                                     torqueCommand_pct, ...
                                     speedLimit_rpm)


            %% ========================================================
            % 1. SPEED LIMIT
            % ========================================================

            speedLim = double(speedLimit_rpm);


            if ~isfinite(speedLim)
                speedLim = 0;
            end


            speedLim = min( ...
                max(speedLim,0), ...
                obj.MaxSpeed_rpm);


            % P1.009 resolution = 0.1 rpm
            speedLimRaw = ...
                uint32(round(speedLim * 10));


            % Only write if value changes
            if speedLimRaw ~= obj.lastSpeedLimitRaw

                speedLow = bitand( ...
                    speedLimRaw, ...
                    uint32(65535));

                speedHigh = bitshift( ...
                    speedLimRaw, ...
                    -16);


                speedWords = double([ ...
                    speedLow, ...
                    speedHigh]);


                writeRegisters(obj, ...
                    'holdingregs', ...
                    275, ...
                    speedWords, ...
                    obj.ServoID, ...
                    'uint16');


                obj.lastSpeedLimitRaw = speedLimRaw;

            end


            %% ========================================================
            % 2. TORQUE COMMAND
            % ========================================================

            cmd = round(double(torqueCommand_pct));


            if ~isfinite(cmd)
                cmd = 0;
            end


            cmd = min( ...
                max(cmd,-obj.MaxTorque_pct), ...
                obj.MaxTorque_pct);


            % Only write if value changes
            if isnan(obj.lastTorqueCommand_pct) || ...
                    cmd ~= obj.lastTorqueCommand_pct

                writeRegisters(obj, ...
                    'holdingregs', ...
                    281, ...
                    cmd, ...
                    obj.ServoID, ...
                    'int16');


                obj.lastTorqueCommand_pct = cmd;

            end


            command_pct = double(cmd);


            %% ========================================================
            % 3. SERVO FEEDBACK
            %
            % 19/20 = speed
            % 21/22 = torque
            % ========================================================

            servoRaw = readRegisters(obj, ...
                'holdingregs', ...
                19, ...
                4, ...
                obj.ServoID, ...
                'uint16');


            %% Speed

            speedRaw = decodeServo32( ...
                obj, ...
                servoRaw(1), ...
                servoRaw(2));


            speed_rpm = ...
                double(speedRaw) / 10;


            %% Torque

            torqueRaw = decodeServo32( ...
                obj, ...
                servoRaw(3), ...
                servoRaw(4));


            actualTorque_pct = ...
                double(torqueRaw) / 10;


            %% ========================================================
            % 4. SOCOMEC
            %
            % ONE read per 0.1 s
            %
            % IMPORTANT:
            % Socomec does NOT retry during stepImpl.
            %
            % If a packet fails, previous valid data is used immediately.
            % This prevents the power meter from making the model slow.
            % ========================================================

            try

                %% ----------------------------------------------------
                % COMPLETE SOCOMEC REGISTER BLOCK
                %
                % MATLAB address 50515
                % 30 x uint16 registers
                % -----------------------------------------------------

                meterRaw = readMeterRegisters(obj, ...
                    'holdingregs', ...
                    50515, ...
                    30, ...
                    obj.PowerMeterID, ...
                    'uint16');


                %% ----------------------------------------------------
                % LINE-TO-LINE VOLTAGES
                % -----------------------------------------------------

                U12 = decodeSocomecUInt32( ...
                    obj, ...
                    meterRaw(1), ...
                    meterRaw(2));

                U23 = decodeSocomecUInt32( ...
                    obj, ...
                    meterRaw(3), ...
                    meterRaw(4));

                U31 = decodeSocomecUInt32( ...
                    obj, ...
                    meterRaw(5), ...
                    meterRaw(6));


                VLL_V = double([ ...
                    U12;
                    U23;
                    U31]) / 100;


                %% ----------------------------------------------------
                % LINE-TO-NEUTRAL VOLTAGES
                % -----------------------------------------------------

                V1 = decodeSocomecUInt32( ...
                    obj, ...
                    meterRaw(7), ...
                    meterRaw(8));

                V2 = decodeSocomecUInt32( ...
                    obj, ...
                    meterRaw(9), ...
                    meterRaw(10));

                V3 = decodeSocomecUInt32( ...
                    obj, ...
                    meterRaw(11), ...
                    meterRaw(12));


                VLN_V = double([ ...
                    V1;
                    V2;
                    V3]) / 100;


                %% ----------------------------------------------------
                % FREQUENCY
                % -----------------------------------------------------

                F = decodeSocomecUInt32( ...
                    obj, ...
                    meterRaw(13), ...
                    meterRaw(14));


                Frequency_Hz = ...
                    double(F) / 100;


                %% ----------------------------------------------------
                % CURRENTS
                % -----------------------------------------------------

                I1 = decodeSocomecUInt32( ...
                    obj, ...
                    meterRaw(15), ...
                    meterRaw(16));

                I2 = decodeSocomecUInt32( ...
                    obj, ...
                    meterRaw(17), ...
                    meterRaw(18));

                I3 = decodeSocomecUInt32( ...
                    obj, ...
                    meterRaw(19), ...
                    meterRaw(20));

                In = decodeSocomecUInt32( ...
                    obj, ...
                    meterRaw(21), ...
                    meterRaw(22));


                I_A = double([ ...
                    I1;
                    I2;
                    I3]) / 1000;


                NeutralCurrent_A = ...
                    double(In) / 1000;


                %% ----------------------------------------------------
                % ACTIVE POWER
                % -----------------------------------------------------

                P = decodeSocomecInt32( ...
                    obj, ...
                    meterRaw(23), ...
                    meterRaw(24));


                %% ----------------------------------------------------
                % REACTIVE POWER
                % -----------------------------------------------------

                Q = decodeSocomecInt32( ...
                    obj, ...
                    meterRaw(25), ...
                    meterRaw(26));


                %% ----------------------------------------------------
                % APPARENT POWER
                % -----------------------------------------------------

                S = decodeSocomecUInt32( ...
                    obj, ...
                    meterRaw(27), ...
                    meterRaw(28));


                %% ----------------------------------------------------
                % POWER FACTOR
                % -----------------------------------------------------

                PF = decodeSocomecInt32( ...
                    obj, ...
                    meterRaw(29), ...
                    meterRaw(30));


                %% ----------------------------------------------------
                % SCALING
                %
                % Preserved from your current code.
                % -----------------------------------------------------

                ActivePower_kW = ...
                    double(P) / 100;

                ReactivePower_kVAr = ...
                    double(Q) / 100;

                ApparentPower_kVA = ...
                    double(S) / 100;


                PowerFactor = ...
                    double(PF) / 1000;


                %% ----------------------------------------------------
                % COMPLETE POWER-METER PACKET
                % -----------------------------------------------------

                newMeterValues = [ ...
                    VLL_V;
                    VLN_V;
                    I_A;
                    ActivePower_kW;
                    ReactivePower_kVAr;
                    ApparentPower_kVA;
                    PowerFactor;
                    Frequency_Hz;
                    NeutralCurrent_A];


                %% ----------------------------------------------------
                % VALIDATE VALUES
                % -----------------------------------------------------

                if all(isfinite(newMeterValues))

                    obj.lastMeterValues = ...
                        newMeterValues;

                    obj.meterWarningIssued = false;

                else

                    error( ...
                        'DrivetrainModbusIO:InvalidMeterData', ...
                        'Socomec packet contains NaN or Inf.');

                end


            catch ME

                %% ----------------------------------------------------
                % SOCOMEC FAILED THIS SAMPLE
                %
                % Do NOT terminate simulation.
                %
                % Use previous valid values.
                % -----------------------------------------------------

                if ~obj.meterWarningIssued

                    warning( ...
                        'DrivetrainModbusIO:SocomecRead', ...
                        ['Socomec read failed. ' ...
                         'Using previous valid data. Error: %s'], ...
                        ME.message);

                    obj.meterWarningIssued = true;

                end


                meter = obj.lastMeterValues;


                VLL_V = meter(1:3);

                VLN_V = meter(4:6);

                I_A = meter(7:9);


                ActivePower_kW = ...
                    meter(10);

                ReactivePower_kVAr = ...
                    meter(11);

                ApparentPower_kVA = ...
                    meter(12);

                PowerFactor = ...
                    meter(13);

                Frequency_Hz = ...
                    meter(14);

                NeutralCurrent_A = ...
                    meter(15);

            end


            %% ========================================================
            % 5. COMBINED OUTPUT
            %
            % 18 VALUES
            % ========================================================

            AllData = [ ...
                actualTorque_pct;
                speed_rpm;
                command_pct;
                VLL_V;
                VLN_V;
                I_A;
                ActivePower_kW;
                ReactivePower_kVAr;
                ApparentPower_kVA;
                PowerFactor;
                Frequency_Hz;
                NeutralCurrent_A];

        end


        %% ============================================================
        % RELEASE
        % ============================================================
        function releaseImpl(obj)

            %% Zero torque first

            try

                writeRegisters(obj, ...
                    'holdingregs', ...
                    281, ...
                    0, ...
                    obj.ServoID, ...
                    'int16');

            catch
            end


            %% Servo software DI OFF

            try

                writeRegisters(obj, ...
                    'holdingregs', ...
                    1039, ...
                    hex2dec('0000'), ...
                    obj.ServoID, ...
                    'uint16');

            catch
            end


            %% Release COM port

            obj.m = [];


            %% Reset states

            obj.lastSpeedLimitRaw = ...
                uint32(4294967295);

            obj.lastTorqueCommand_pct = NaN;

            obj.servoEnabled = false;


            obj.lastMeterValues = ...
                zeros(15,1);

            obj.lastMeterValues(14) = 50;


            obj.meterWarningIssued = false;

        end


        %% ============================================================
        % SAMPLE TIME
        % ============================================================
        function sts = getSampleTimeImpl(obj)

            sts = createSampleTime( ...
                obj, ...
                'Type', ...
                'Discrete', ...
                'SampleTime', ...
                obj.SampleTime);

        end


        %% ============================================================
        % NUMBER OF INPUTS
        % ============================================================
        function n = getNumInputsImpl(~)

            n = 2;

        end


        %% ============================================================
        % OUTPUT SIZES
        % ============================================================
        function [s1,s2,s3,s4,s5,s6,s7,s8,s9,s10,s11,s12,s13] = ...
                getOutputSizeImpl(~)

            s1 = [1 1];
            s2 = [1 1];
            s3 = [1 1];

            s4 = [3 1];
            s5 = [3 1];
            s6 = [3 1];

            s7 = [1 1];
            s8 = [1 1];
            s9 = [1 1];

            s10 = [1 1];
            s11 = [1 1];
            s12 = [1 1];

            s13 = [18 1];

        end


        %% ============================================================
        % OUTPUT DATA TYPES
        % ============================================================
        function [d1,d2,d3,d4,d5,d6,d7,d8,d9,d10,d11,d12,d13] = ...
                getOutputDataTypeImpl(~)

            d1 = 'double';
            d2 = 'double';
            d3 = 'double';

            d4 = 'double';
            d5 = 'double';
            d6 = 'double';

            d7 = 'double';
            d8 = 'double';
            d9 = 'double';

            d10 = 'double';
            d11 = 'double';
            d12 = 'double';

            d13 = 'double';

        end


        %% ============================================================
        % OUTPUT COMPLEXITY
        % ============================================================
        function [c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13] = ...
                isOutputComplexImpl(~)

            c1 = false;
            c2 = false;
            c3 = false;

            c4 = false;
            c5 = false;
            c6 = false;

            c7 = false;
            c8 = false;
            c9 = false;

            c10 = false;
            c11 = false;
            c12 = false;

            c13 = false;

        end


        %% ============================================================
        % FIXED OUTPUT SIZES
        % ============================================================
        function [f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13] = ...
                isOutputFixedSizeImpl(~)

            f1 = true;
            f2 = true;
            f3 = true;

            f4 = true;
            f5 = true;
            f6 = true;

            f7 = true;
            f8 = true;
            f9 = true;

            f10 = true;
            f11 = true;
            f12 = true;

            f13 = true;

        end


        %% ============================================================
        % INPUT NAMES
        % ============================================================
        function [n1,n2] = getInputNamesImpl(~)

            n1 = 'TorqueCommand_pct';

            n2 = 'SpeedLimit_rpm';

        end


        %% ============================================================
        % OUTPUT NAMES
        % ============================================================
        function [n1,n2,n3,n4,n5,n6,n7,n8,n9,n10,n11,n12,n13] = ...
                getOutputNamesImpl(~)

            n1 = 'ActualTorque_pct';

            n2 = 'Speed_rpm';

            n3 = 'CommandTorque_pct';


            n4 = 'VLL_V';

            n5 = 'VLN_V';

            n6 = 'PhaseCurrent_A';


            n7 = 'ActivePower_kW';

            n8 = 'ReactivePower_kVAr';

            n9 = 'ApparentPower_kVA';


            n10 = 'PowerFactor';

            n11 = 'Frequency_Hz';

            n12 = 'NeutralCurrent_A';


            n13 = 'AllData';

        end

    end


    %% ================================================================
    % PRIVATE METHODS
    % ================================================================
    methods (Access = private)


        %% ============================================================
        % MODBUS WRITE WITH RETRY
        %
        % Used for servo writes.
        % ============================================================
        function writeRegisters(obj, varargin)

            for attempt = 1:obj.MaxModbusAttempts

                try

                    write( ...
                        obj.m, ...
                        varargin{:});


                    pause( ...
                        obj.InterTransactionDelay);


                    return;


                catch ME

                    retryable = ...
                        isRetryableModbusError( ...
                        obj, ...
                        ME);


                    if retryable && ...
                            attempt < obj.MaxModbusAttempts

                        pause( ...
                            obj.RetryDelay);

                    else

                        rethrow(ME);

                    end

                end

            end

        end


        %% ============================================================
        % MODBUS READ WITH RETRY
        %
        % Used for servo reads.
        % ============================================================
        function data = readRegisters(obj, varargin)

            data = [];


            for attempt = 1:obj.MaxModbusAttempts

                try

                    data = read( ...
                        obj.m, ...
                        varargin{:});


                    pause( ...
                        obj.InterTransactionDelay);


                    return;


                catch ME

                    retryable = ...
                        isRetryableModbusError( ...
                        obj, ...
                        ME);


                    if retryable && ...
                            attempt < obj.MaxModbusAttempts

                        pause( ...
                            obj.RetryDelay);

                    else

                        rethrow(ME);

                    end

                end

            end

        end


        %% ============================================================
        % SOCOMEC READ
        %
        % ONE ATTEMPT ONLY.
        %
        % If this read fails, stepImpl uses previous valid values.
        % ============================================================
        function data = readMeterRegisters(obj, varargin)

            data = read( ...
                obj.m, ...
                varargin{:});


            pause( ...
                obj.InterTransactionDelay);

        end


        %% ============================================================
        % IDENTIFY RETRYABLE MODBUS ERROR
        % ============================================================
        function retryable = ...
                isRetryableModbusError(~, ME)

            msg = lower(ME.message);


            retryable = ...
                contains(msg,'crc') || ...
                contains(msg,'timeout') || ...
                contains(msg,'timed out') || ...
                contains(msg,'failed to receive') || ...
                contains(msg,'no response') || ...
                contains(msg,'invalid response') || ...
                contains(msg,'communication error');

        end


        %% ============================================================
        % DELTA SIGNED 32-BIT DECODER
        %
        % LOW word first
        % HIGH word second
        % ============================================================
        function value = decodeServo32( ...
                ~, ...
                lowWord, ...
                highWord)

            lo = uint32(lowWord);

            hi = uint32(highWord);


            raw32 = bitor( ...
                lo, ...
                bitshift(hi,16));


            if raw32 >= uint32(2147483648)

                value = ...
                    double(raw32) - ...
                    4294967296;

            else

                value = ...
                    double(raw32);

            end

        end


        %% ============================================================
        % SOCOMEC UNSIGNED 32-BIT DECODER
        %
        % HIGH word first
        % LOW word second
        % ============================================================
        function value = decodeSocomecUInt32( ...
                ~, ...
                highWord, ...
                lowWord)

            hi = uint32(highWord);

            lo = uint32(lowWord);


            raw32 = bitor( ...
                bitshift(hi,16), ...
                lo);


            value = ...
                double(raw32);

        end


        %% ============================================================
        % SOCOMEC SIGNED 32-BIT DECODER
        % ============================================================
        function value = decodeSocomecInt32( ...
                ~, ...
                highWord, ...
                lowWord)

            hi = uint32(highWord);

            lo = uint32(lowWord);


            raw32 = bitor( ...
                bitshift(hi,16), ...
                lo);


            if raw32 >= uint32(2147483648)

                value = ...
                    double(raw32) - ...
                    4294967296;

            else

                value = ...
                    double(raw32);

            end

        end

    end


    %% ================================================================
    % SIMULINK EXECUTION MODE
    % ================================================================
    methods (Static, Access = protected)

        function mode = getSimulateUsingImpl

            mode = ...
                'Interpreted execution';

        end

    end

end
