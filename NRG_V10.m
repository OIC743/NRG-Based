%% =========================================================================
%  ENERGY-BASED LIQUEFACTION ANALYSIS FOR CYCLIC SIMPLE SHEAR TESTS
%  MICP-treated silty sands  |  BATCH PROCESSING  |  NRG_V10  Oct 7th, 2026
%  =========================================================================
%
%  1. BATCH FILE SELECTION (GUI)  - folder, file list, e0 per specimen
%  2. RUN OPTIONS (GUI)           - criterion, thresholds, outputs
%  3. INITIALIZATION              - folders, log, results table
%  4. BATCH LOOP                  - each file analysed in its own try/catch;
%                                   a failed file is recorded and skipped
%
%  Figures are generated invisibly and written straight to PDF. Each test
%  produces <testID>_CSR<x.xx>_<criterion>_NL<x.xx>.xlsx and a PDF with the
%  same base name. Figures exported: 01, 02, 03 (pore pressure), 05
%  (gamma_DA only), 06, 07, 08 (W vs gamma_DA), 14, 19.
%
%  CYCLES:  a cycle runs from one measured tau = 0 crossing to the next
%           in the direction of the first loading; every loop starts and
%           ends exactly on tau = 0.
%  ENERGY:  W = int tau d(gamma), computed with cumtrapz only.
%  PORE PRESSURE per cycle:
%     R_u,max = highest R_u(t) in each half cycle (between shear-stress
%               reversals), at the N where it occurs; an upper envelope
%               through them bounds R_u(t) from above
%     R_u,res = R_u(t) at the final data point of each cycle
%     both series start at N = 0, R_u = 0 and are joined by smooth
%     curves (pchip) that pass through every point.
%
%  FILE NAMING:  CYC161-NT-0-0.66-100-0.15c
%                 |      |  | |    |   +-- CSR (trailing letter = repeat)
%                 |      |  | |    +------ vertical stress, kPa
%                 |      |  | +----------- initial void ratio
%                 |      |  +------------- fines content, %
%                 |      +---------------- treatment (NT | MICP)
%                 +----------------------- test type + sand
%
%  Version: V10 (NRG_V10.m)
%           V10: R_u,max = half-cycle maxima between shear-stress
%                reversals; R_u,max envelope that bounds R_u(t) from
%                above; Fig03 colours R_u(t) by cycle (Fig02 ramp).
%           V9: N_L and W for every criterion with its own threshold
%               (new Criteria sheet; NaN when a criterion never fires);
%               stiffness criterion interpolated between cycles like DA;
%               Seed-Booker fit and Fig09 removed.
%           V8: DA criterion by linear interpolation in gamma_DA between
%               the cycles either side of the threshold, on the curve of
%               cumulative W vs gamma_DA (new Fig08); W_at_DA reported.
%           V7: Ru criterion on the measured R_u(t) (look-ahead envelope
%               removed); DA = peak-to-peak strain between consecutive
%               strain reversals, trigger at the sample where it is
%               reached; G_sec and damping from
%               loop-centred amplitudes; one CSR definition in every
%               sheet; Davis-Berrill fit removed.
%           V6: cycles are cut where the measured shear stress crosses
%               zero (with a noise band), not by the hardware counter;
%               an interpolated tau = 0 point closes every loop. The
%               counter is kept only as a logged cross-check.
%           V5: R_u,max is one value per cycle - the cycle's highest
%               R_u(t), placed at the N where it occurs; the V4 peak
%               search and its two thresholds are removed.
%           V4: R_u,max redefined as the local maxima of R_u(t); Fig03
%               fits replaced by smooth curves (pchip) through the points;
%               Excel gets Ru_res and Ru_max sheets; R_u,res Seed-Booker
%               fit removed.
%           V3: polyarea removed - energy and damping from cumtrapz only;
%               R_u,max and R_u,res defined per cycle (start at 0) and
%               exported to Excel; new Fig03 pore-pressure figure with
%               Seed-Booker fits for R_u,max and R_u,res.
%           V2: figure set trimmed; paper/diagnostic mode removed; Excel
%               and PDF outputs share one base name.
%           V1: original script (internal label v5).
%           MATLAB R2020a or later; the expert selector needs uifigure,
%           uigridlayout, uislider, uispinner and uiconfirm
%  =========================================================================

clc; clear; close all;

%% ======================= 1. BATCH FILE SELECTION =========================

config = defaultConfig();

batch = selectBatchFiles(config);
if isempty(batch)
    fprintf('No files selected - analysis cancelled.\n');
    return
end

%% ======================= 2. RUN OPTIONS ==================================

[config, okRun] = analysisOptionsGUI(config);
if ~okRun
    fprintf('Analysis cancelled at the options window.\n');
    return
end

%% ======================= 3. INITIALIZATION ===============================

config = validateConfig(config);

dataFolder = batch.Properties.UserData.folder;
outputDir  = fullfile(dataFolder, config.output.subFolder);
if ~isfolder(outputDir)
    [okMk, msgMk] = mkdir(outputDir);
    if ~okMk
        error('liq:init:outputDir', 'Cannot create output folder "%s": %s', ...
              outputDir, msgMk);
    end
end

runStamp = char(datetime('now', 'Format', 'yyyy-MM-dd_HHmmss'));

logFile = fullfile(outputDir, sprintf('analysis_log_%s.txt', runStamp));
logFID  = fopen(logFile, 'w');
if logFID < 0
    warning('liq:init:log', 'Could not open a log file; logging to screen only.');
    logFID = [];
end
cleanupLog = onCleanup(@() closeLog(logFID));

As_mm2 = (pi/4) * config.specimen.diameter^2;
As_m2  = (pi/4) * (config.specimen.diameter/1000)^2;
H_0    = config.specimen.height;

picksFile   = fullfile(dataFolder, config.expert.picksFile);
expertPicks = readExpertPicks(picksFile);

nFiles  = height(batch);
results = initResultsTable(batch);

logf(logFID, '\n  ENERGY-BASED LIQUEFACTION ANALYSIS - BATCH RUN\n');
logf(logFID, '  %s\n', repmat('=', 1, 76));
logf(logFID, '  Started       : %s\n', char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
logf(logFID, '  Data folder   : %s\n', dataFolder);
logf(logFID, '  Output folder : %s\n', outputDir);
logf(logFID, '  Files         : %d\n', nFiles);
logf(logFID, '  Specimen      : D = %.2f mm, H0 = %.2f mm, A = %.1f mm^2\n', ...
     config.specimen.diameter, H_0, As_mm2);
logf(logFID, '  Criterion     : %s (thresholds: SA %.2f%%, DA %.2f%%, Ru %.2f, G/G1 %.2f)\n', ...
     config.criteria.primary, config.criteria.gamma_SA*100, ...
     config.criteria.gamma_DA*100, config.criteria.Ru, config.criteria.G_ratio);
logf(logFID, '  Not triggered : report %s\n', upper(config.criteria.onNotTriggered));
logf(logFID, '  Expert mode   : %s   (stored picks: %d)\n', ...
     config.expert.mode, expertPicks.Count);
logf(logFID, '  Excel/Figures : %s / %s\n', onOffStr(config.output.excel), ...
     onOffStr(config.output.figures));
logf(logFID, '  %s\n\n', repmat('=', 1, 76));

%% ======================= 4. BATCH LOOP ===================================

nOK = 0; nFailed = 0;
tRun = tic;

for k = 1:nFiles

    testFile = batch.File{k};
    [~, testID] = fileparts(testFile);
    filePath = fullfile(dataFolder, testFile);

    logf(logFID, '  %s\n', repmat('-', 1, 76));
    logf(logFID, '  [%d/%d] %s\n', k, nFiles, testFile);

    tFile = tic;
    figsBefore = findall(groot, 'Type', 'figure');

    try
        spec = struct();
        spec.testID    = testID;
        spec.fileName  = testFile;
        spec.e0        = batch.e0(k);
        spec.sand      = batch.Sand{k};
        spec.treatment = batch.Treatment{k};
        spec.FC_pct    = batch.FC_pct(k);
        spec.CSR_name  = batch.CSR_name(k);
        spec.diameter  = config.specimen.diameter;
        spec.height    = H_0;
        spec.As_mm2    = As_mm2;
        spec.As_m2     = As_m2;

        if ~isfinite(spec.e0)
            error('liq:file:e0', 'Initial void ratio is not defined for this file.');
        end

        R = analyzeOneFile(filePath, spec, config, outputDir, ...
                           expertPicks, picksFile, logFID);

        % ---- fill the results row ------------------------------------
        results.nPointsConsol(k) = R.nPointsConsol;
        results.nPointsShear(k)  = R.nPointsShear;
        results.deltaH_mm(k)     = R.deltaH;
        results.e_ps(k)          = R.e_ps;
        results.sigma_v0_kPa(k)  = R.sigma_v0_kPa;
        results.CSR(k)           = R.CSR;
        results.nCycles(k)       = R.nCompleteCycles;
        results.N_L(k)           = R.N_L;
        results.N_L_SA(k)        = R.N_L_SA;
        results.N_L_DA(k)        = R.N_L_DA;
        results.N_L_Ru(k)        = R.N_L_Ru;
        results.N_L_Stiff(k)     = R.N_L_Stiff;
        results.N_L_Expert(k)    = R.N_L_Expert;
        results.Ru_at_liq(k)     = R.Ru_at_liq;
        results.Ru_max_at_liq(k) = R.Ru_max_at_liq;
        results.Ru_res_at_liq(k) = R.Ru_res_at_liq;
        results.W_at_liq_Jm3(k)  = R.W_at_liq;
        results.Wn_at_liq(k)     = R.Wn_at_liq;
        results.W_pos_Jm3(k)     = R.W_pos_at_liq;
        results.W_neg_Jm3(k)     = R.W_neg_at_liq;
        results.W_at_DA_Jm3(k)   = R.W_at_DA;
        results.Wn_at_DA(k)      = R.Wn_at_DA;
        results.EnergyRecovery(k)= R.Energy_recovery_at_liq;
        results.G_sec1_MPa(k)    = R.G_sec1_MPa;
        results.W_at_SA_Jm3(k)   = R.W_at_SA;
        results.W_at_Ru_Jm3(k)   = R.W_at_Ru;
        results.W_at_Stiff_Jm3(k)= R.W_at_Stiff;
        results.W_at_Expert_Jm3(k) = R.W_at_Expert;
        results.tau_res_ratio(k) = R.tau_res_ratio;
        results.cumAbsGamma_pct(k) = R.cum_abs_gamma_at_liq_pct;
        results.epsV_max_pct(k)  = R.epsilon_v_max_pct;
        results.Criterion{k}     = R.criterionLabel;
        results.Liquefied{k}     = ternary(R.liquefied, 'yes', 'no');
        results.Status{k}        = 'OK';
        results.Message{k}       = R.note;

        nOK = nOK + 1;
        logf(logFID, '     OK  | N_L = %s | W = %s J/m3 | Ru = %s | %.1f s\n', ...
             fmtNum(R.N_L,'%.2f'), fmtNum(R.W_at_liq,'%.1f'), ...
             fmtNum(R.Ru_at_liq,'%.3f'), toc(tFile));

    catch ME
        nFailed = nFailed + 1;
        results.Status{k}  = 'FAILED';
        results.Message{k} = ME.message;
        logf(logFID, '     FAILED - %s\n', ME.message);
        if ~isempty(ME.stack)
            logf(logFID, '              (%s, line %d)\n', ME.stack(1).name, ME.stack(1).line);
        end
        closeNewFigures(figsBefore);
        if ~config.batch.continueOnError
            logf(logFID, '\n  continueOnError is false - batch stopped.\n');
            rethrow(ME);
        end
        continue
    end

    closeNewFigures(figsBefore);   % nothing is left on screen
end

%% ======================= 5. BATCH SUMMARY ================================

logf(logFID, '\n  %s\n', repmat('=', 1, 76));
logf(logFID, '  BATCH COMPLETE - %d of %d processed, %d failed  (%.1f s)\n', ...
     nOK, nFiles, nFailed, toc(tRun));
logf(logFID, '  %s\n', repmat('=', 1, 76));

if nFailed > 0
    logf(logFID, '\n  Files that failed:\n');
    idxFail = find(strcmp(results.Status, 'FAILED'));
    for i = 1:numel(idxFail)
        logf(logFID, '   - %-45s %s\n', results.File{idxFail(i)}, ...
             results.Message{idxFail(i)});
    end
end

if config.output.excel
    masterFile = fullfile(outputDir, sprintf('%s_%s', runStamp, config.output.masterFile));
    try
        writetable(results, masterFile, 'Sheet', 'Summary');
        logf(logFID, '\n  Master results : %s\n', masterFile);
    catch ME
        logf(logFID, '\n  Could not write master results: %s\n', ME.message);
    end
end

logf(logFID, '  Log file       : %s\n\n', logFile);

clear cleanupLog


%% =========================================================================
%  PER-FILE ANALYSIS
%  =========================================================================

function R = analyzeOneFile(filePath, spec, config, outputDir, ...
                            expertPicks, picksFile, logFID)
%ANALYZEONEFILE  Full energy-based liquefaction analysis of one CSS test.

R = struct();
R.note = '';

% ======================= INITIALIZATION =================================
H_0    = spec.height;
e_0    = spec.e0;
As_m2  = spec.As_m2;
testID = spec.testID;

% ======================= DATA IMPORT ====================================
[~, phase1, phase2] = importTestFile(filePath, config);

nPoints = size(phase2, 1);
R.nPointsConsol = size(phase1, 1);
R.nPointsShear  = nPoints;

% ======================= POST-CONSOLIDATION VOID RATIO ==================
if ~isempty(phase1)
    AD_Z_consol = phase1(:, config.col.disp_V);
    AD_Z_consol = AD_Z_consol(isfinite(AD_Z_consol));
    if isempty(AD_Z_consol)
        deltaH = 0;
    else
        deltaH = abs(min(AD_Z_consol));
    end
else
    deltaH = 0;
end

H_ps    = H_0 - deltaH;
if H_ps <= 0
    error('liq:state:height', ...
          'Post-consolidation height is non-positive (deltaH = %.3f mm).', deltaH);
end
e_ps    = (H_ps * (1 + e_0)) / H_0 - 1;
delta_e = e_ps - e_0;
Hf      = H_ps;

R.deltaH = deltaH;
R.e_ps   = e_ps;

% ======================= DATA EXTRACTION ================================
time       = phase2(:,config.col.time) - phase2(1,config.col.time);
F_H_raw    = phase2(:,config.col.F_H);
F_V        = phase2(:,config.col.F_V);
disp_H_raw = phase2(:,config.col.disp_H);
disp_V_raw = phase2(:,config.col.disp_V);
cycleRaw   = phase2(:,config.col.cycle);

disp_H = disp_H_raw - disp_H_raw(1);
F_H    = F_H_raw - F_H_raw(1);

% ======================= CYCLE SEPARATION ===============================
% Cycles are cut where the MEASURED shear stress crosses zero in the
% direction of the first loading, not by the hardware cycle counter: the
% counter runs on its own clock and drifts against the measured response,
% which left loops ending below tau = 0. At each crossing one point is
% added on the straight line between the two bracketing samples (all
% channels interpolated at the same fraction, tau exactly 0). It ends
% cycle c and starts cycle c+1, so every loop is closed on the tau = 0
% axis. The added point lies on the segment the trapezoidal rule already
% integrates, so cumtrapz energy is unchanged.
X = [time, F_H, F_V, disp_H, disp_V_raw];
[X, bnd, bndOrig] = splitAtZeroShear(X, 2, config.cycles.zeroBandFrac);
time       = X(:,1);
F_H        = X(:,2);
F_V        = X(:,3);
disp_H     = X(:,4);
disp_V_raw = X(:,5);
nPoints    = size(X, 1);

nCompleteCycles = numel(bnd) - 1;
if nCompleteCycles < 1
    error('liq:cycles:none', ...
          'No complete cycle: shear stress never returned through zero.');
end
cycleNumbers    = (1:nCompleteCycles)';
cycStart        = bnd(1:end-1);              % shared with the previous end
cycleEndIdx     = bnd(2:end);
meanCycleLength = mean(diff(bnd));           % samples per closed cycle
R.nCompleteCycles = nCompleteCycles;

% Fractional cycle number: linear in sample index inside each closed
% cycle (boundaries fall exactly on N = 1, 2, ...); samples after the last
% boundary belong to an unfinished cycle and use the mean cycle length.
FCN = zeros(nPoints, 1);
for c = 1:nCompleteCycles
    ii = (cycStart(c):cycleEndIdx(c))';
    FCN(ii) = (c - 1) + (ii - cycStart(c)) / (cycleEndIdx(c) - cycStart(c));
end
if cycleEndIdx(end) < nPoints
    ii = (cycleEndIdx(end)+1:nPoints)';
    FCN(ii) = nCompleteCycles + (ii - cycleEndIdx(end)) / meanCycleLength;
end

% Cross-check against the hardware counter: how far (in samples) each
% tau = 0 boundary lies after the counter's own cycle change.
cntChange = find(diff(cycleRaw) ~= 0 & isfinite(diff(cycleRaw))) + 1;
nPair     = min(numel(cntChange), numel(bndOrig) - 1);
if nPair > 0
    lagCnt = bndOrig(2:nPair+1) - cntChange(1:nPair);
    logf(logFID, ['     Cycles: %d closed at tau = 0 (%d points added); ' ...
                  'counter lag %.1f to %.1f samples\n'], nCompleteCycles, ...
         nPoints - R.nPointsShear, min(lagCnt), max(lagCnt));
else
    logf(logFID, '     Cycles: %d closed at tau = 0 (%d points added)\n', ...
         nCompleteCycles, nPoints - R.nPointsShear);
end

tau_Pa  = F_H ./ As_m2;
tau_kPa = tau_Pa ./ 1000;

gamma     = disp_H ./ Hf;
gamma_pct = gamma .* 100;

sigma_Pa  = F_V ./ As_m2;
sigma_kPa = sigma_Pa ./ 1000;

sigma_v0_kPa = max(sigma_kPa);
if ~isfinite(sigma_v0_kPa) || sigma_v0_kPa <= 0
    error('liq:state:sigmaV0', ...
          'Invalid sigma_v0 = %.4f kPa. Check the vertical load channel.', ...
          sigma_v0_kPa);
end
sigma_v0_Pa  = sigma_v0_kPa * 1000;
sigma_norm   = sigma_kPa ./ sigma_v0_kPa;
tau_norm     = tau_kPa ./ sigma_v0_kPa;

R.sigma_v0_kPa = sigma_v0_kPa;

Ru = (sigma_v0_kPa - sigma_kPa) ./ sigma_v0_kPa;
Ru = max(0, min(1, Ru));

disp_V        = disp_V_raw - disp_V_raw(1);
epsilon_v     = disp_V ./ Hf;
epsilon_v_pct = epsilon_v .* 100;
R.epsilon_v_max_pct = max(abs(epsilon_v_pct));

if R.epsilon_v_max_pct > config.qa.epsilon_v_warn_pct
    R.note = sprintf('eps_v max %.3f%% exceeds %.2f%% - check compliance', ...
                     R.epsilon_v_max_pct, config.qa.epsilon_v_warn_pct);
end

% ======================= PER-CYCLE DATA ================================
Data = [time, F_H, disp_H, F_V, FCN, tau_kPa, gamma, ...
        gamma_pct, sigma_kPa, sigma_Pa, tau_Pa];

% Each cell is one closed loop, from its tau = 0 start to its tau = 0 end
% (the boundary point is shared by consecutive cycles).
AC_complete = cell(nCompleteCycles, 1);
for c = 1:nCompleteCycles
    AC_complete{c} = Data(cycStart(c):cycleEndIdx(c), :);
end

% ======================= CYCLE-BY-CYCLE PARAMETERS ======================
tau_max   = zeros(nCompleteCycles,1);  tau_min   = zeros(nCompleteCycles,1);
gamma_max = zeros(nCompleteCycles,1);  gamma_min = zeros(nCompleteCycles,1);
sigma_min = zeros(nCompleteCycles,1);
sigma_end = zeros(nCompleteCycles,1);

apex_tau_a   = zeros(nCompleteCycles,1);  apex_tau_b   = zeros(nCompleteCycles,1);
apex_gamma_a = zeros(nCompleteCycles,1);  apex_gamma_b = zeros(nCompleteCycles,1);

for c = 1:nCompleteCycles
    cycleData = AC_complete{c};

    cyc_tau    = cycleData(:, 6);
    cyc_gamma  = cycleData(:, 7);
    cyc_sigma  = cycleData(:, 9);

    tau_max(c)   = max(cyc_tau);
    tau_min(c)   = min(cyc_tau);
    gamma_max(c) = max(cyc_gamma);
    gamma_min(c) = min(cyc_gamma);
    sigma_min(c) = min(cyc_sigma);
    sigma_end(c) = cyc_sigma(end);   % last recorded point of the cycle,
                                      % used for R_u,res (see below)

    % Loop tips (strain reversal points): a = largest gamma while tau > 0,
    % b = smallest gamma while tau < 0. Restricting each tip to its own
    % half of the loop keeps it on the correct branch even when strain
    % has accumulated to one side.
    pos = find(cyc_tau > 0);
    neg = find(cyc_tau < 0);
    if isempty(pos) || isempty(neg)
        apex_gamma_a(c) = NaN; apex_tau_a(c) = NaN;
        apex_gamma_b(c) = NaN; apex_tau_b(c) = NaN;
    else
        [~, k] = max(cyc_gamma(pos));  ia = pos(k);
        [~, k] = min(cyc_gamma(neg));  ib = neg(k);
        apex_gamma_a(c) = cyc_gamma(ia); apex_tau_a(c) = cyc_tau(ia);
        apex_gamma_b(c) = cyc_gamma(ib); apex_tau_b(c) = cyc_tau(ib);
    end
end

% Secant shear modulus: slope of the line joining the two loop tips,
%   G_sec = tau_c / gamma_c,  tau_c = (tau_a - tau_b)/2,
%                             gamma_c = (gamma_a - gamma_b)/2,
% i.e. amplitudes measured about the loop's own centre, not the origin.
tau_c_kPa = (apex_tau_a - apex_tau_b) / 2;
gamma_c   = (apex_gamma_a - apex_gamma_b) / 2;
G_sec_kPa = tau_c_kPa ./ gamma_c;
G_sec_kPa(~(gamma_c > 0) | ~isfinite(G_sec_kPa)) = NaN;

tau_max_norm   = tau_max ./ sigma_v0_kPa;
tau_min_norm   = tau_min ./ sigma_v0_kPa;
sigma_min_norm = sigma_min ./ sigma_v0_kPa;

% Double-amplitude (peak-to-peak) shear strain of each closed cycle, for
% the CycleData table and Fig05. Not |gamma_max| + |gamma_min|: that
% overstates DA whenever the whole loop has drifted to one side of zero.
% (The DA liquefaction criterion below works on the time record.)
gamma_DA  = gamma_max - gamma_min;

% Cyclic strain amplitude used for G_sec and damping (and as the x-axis of
% the modulus-reduction / damping plots): half the tip-to-tip strain.
gamma_cyc = gamma_c;

% ---------------- pore pressure ------------------------------------------
% R_u,max : the highest R_u(t) in each HALF cycle. A cycle produces two
%           R_u peaks, one near each tau = 0 crossing, and one of them often
%           falls just after a cycle boundary. Half cycles are therefore cut
%           at the shear-stress REVERSALS (largest tau while tau > 0,
%           smallest tau while tau < 0), so each window holds one peak.
%           Two values per cycle, each at the N where it occurs.
% R_u,res : RESIDUAL excess pore pressure ratio, R_u at the FINAL data
%           point of each cycle (tau = 0), placed at the end of the cycle.
% Both series are prefixed with N = 0, R_u = 0 (the *_0 vectors).
revIdx = zeros(0, 1);
for c = 1:nCompleteCycles
    ii  = cycStart(c):cycleEndIdx(c);
    tc  = tau_kPa(ii);
    pos = find(tc > 0);
    neg = find(tc < 0);
    if ~isempty(pos), [~, k] = max(tc(pos)); revIdx(end+1, 1) = ii(pos(k)); end %#ok<AGROW>
    if ~isempty(neg), [~, k] = min(tc(neg)); revIdx(end+1, 1) = ii(neg(k)); end %#ok<AGROW>
end
hcEdges   = unique([1; revIdx; cycleEndIdx(end)]);
idx_RuMax = zeros(numel(hcEdges) - 1, 1);
for h = 1:numel(hcEdges) - 1
    [~, k] = max(Ru(hcEdges(h):hcEdges(h+1)));       % first if tied
    idx_RuMax(h) = hcEdges(h) - 1 + k;
end
idx_RuMax = unique(idx_RuMax);      % neighbouring windows share an edge
N_RuMax   = FCN(idx_RuMax);
Ru_max    = Ru(idx_RuMax);
cyc_RuMax = max(1, ceil(N_RuMax));  % cycle each point lies in (N = c is
                                     % the end of cycle c)

% Highest R_u,max of each cycle (CycleData table, dRu/dN, Fig19)
Ru_max_cycle   = nan(nCompleteCycles, 1);
N_Ru_max_cycle = nan(nCompleteCycles, 1);
for c = 1:nCompleteCycles
    kc = find(cyc_RuMax == c);
    if ~isempty(kc)
        [Ru_max_cycle(c), k] = max(Ru_max(kc));
        N_Ru_max_cycle(c)    = N_RuMax(kc(k));
    end
end

sigma_end_norm = sigma_end ./ sigma_v0_kPa;
Ru_res_cycle   = (sigma_v0_kPa - sigma_end) ./ sigma_v0_kPa;
Ru_res_cycle   = max(0, min(1, Ru_res_cycle));

N_max0   = [0; N_RuMax];
Ru_max_0 = [0; Ru_max];
N_res0   = [0; cycleNumbers];
Ru_res_0 = [0; Ru_res_cycle];

% R_u,max envelope: smooth curve (pchip) through (0, 0) and every R_u,max
% point. Where the measured R_u(t) still rises above it by more than
% config.porePressure.envTol - mainly in the first cycle, where R_u climbs
% without forming peaks - the highest such sample is added as a support
% point and the curve rebuilt, so the envelope bounds R_u(t) from above.
envN = N_max0;
envR = Ru_max_0;
mEnv = find(FCN > 0 & FCN <= envN(end));
for it = 1:200
    ex = Ru(mEnv) - smoothThrough(envN, envR, FCN(mEnv));
    [exMax, k] = max(ex);
    if isempty(exMax) || ~(exMax > config.porePressure.envTol), break; end
    [envN, o] = sort([envN; FCN(mEnv(k))]);
    envR      = [envR; Ru(mEnv(k))];
    envR      = envR(o);
end
envIsPeak = ismember(envN, N_max0);  % false = support point

G_sec_MPa = G_sec_kPa / 1000;

G_sec_initial = G_sec_kPa(1);
if ~isfinite(G_sec_initial) || G_sec_initial == 0
    idxG1 = find(isfinite(G_sec_kPa) & G_sec_kPa > 0, 1, 'first');
    if isempty(idxG1)
        error('liq:stiffness:none', ...
              'No valid secant modulus could be computed for any cycle.');
    end
    G_sec_initial = G_sec_kPa(idxG1);
end
G_ratio = G_sec_kPa ./ G_sec_initial;
G_ratio(~isfinite(G_ratio)) = NaN;
R.G_sec1_MPa = G_sec_initial / 1000;

% CSR from the first stable cycles
nCSR_cycles = min(config.qa.CSR_refCycles, nCompleteCycles);
CSR = mean((tau_max(1:nCSR_cycles) - tau_min(1:nCSR_cycles)) / 2) / sigma_v0_kPa;
CSR_per_cycle = ((tau_max - tau_min) / 2) ./ sigma_v0_kPa;
R.CSR = CSR;

% ---------------- cumtrapz energy ----------------
W_running      = cumtrapz(gamma, tau_Pa);
W_running_norm = W_running ./ sigma_v0_Pa;

W_cycle_trapz = zeros(nCompleteCycles, 1);
W_pos_cycle   = zeros(nCompleteCycles, 1);
W_neg_cycle   = zeros(nCompleteCycles, 1);
W_within_cycles     = cell(nCompleteCycles, 1);

for c = 1:nCompleteCycles
    cycleData = AC_complete{c};
    g  = cycleData(:, 7);
    tp = cycleData(:, 11);

    W_within = cumtrapz(g, tp);
    W_cycle_trapz(c)       = W_within(end);
    W_within_cycles{c}     = W_within;

    dGamma  = diff(g);
    tau_avg = (tp(1:end-1) + tp(2:end)) / 2;
    dW      = tau_avg .* dGamma;
    W_pos_cycle(c) = sum(dW(dW > 0));
    W_neg_cycle(c) = sum(dW(dW < 0));
end

W_cumulative_trapz  = cumsum(W_cycle_trapz);
Wn_cycle_trapz      = W_cycle_trapz ./ sigma_v0_Pa;
Wn_cumulative_trapz = cumsum(Wn_cycle_trapz);

% Damping ratio  D = W_D / (4*pi*W_S)
%   W_D : energy dissipated in the cycle = loop area. Because every cycle
%         starts and ends at tau = 0, the elastic energy is zero at both
%         ends and int(tau dgamma) over the cycle is exactly the area.
%   W_S : maximum stored strain energy of the equivalent linear spring,
%         W_S = 1/2 * tau_c * gamma_c  (triangle under the secant line),
%         with the same loop-centred amplitudes as G_sec.
W_S_Jm3 = 0.5 * (tau_c_kPa * 1000) .* gamma_c;
D_ratio = W_cycle_trapz ./ (4 * pi * W_S_Jm3) * 100;
D_ratio(~(W_S_Jm3 > 0) | ~isfinite(D_ratio)) = NaN;

Energy_recovery_ratio = abs(W_neg_cycle) ./ W_pos_cycle;
Energy_recovery_ratio(~isfinite(Energy_recovery_ratio)) = NaN;

% ---------------- rate and accumulation parameters ----------------
dRu_dN      = [0; diff(Ru_max_cycle) ./ diff(cycleNumbers)];
dGammaDA_dN = [0; diff(gamma_DA)   ./ diff(cycleNumbers)];

cum_abs_gamma     = [0; cumsum(abs(diff(gamma)))];
cum_abs_gamma_pct = cum_abs_gamma * 100;

cum_abs_gamma_cycle = zeros(nCompleteCycles, 1);
for c = 1:nCompleteCycles
    cum_abs_gamma_cycle(c) = sum(abs(diff(gamma(cycStart(c):cycleEndIdx(c)))));
end
cum_abs_gamma_cycle_total = cumsum(cum_abs_gamma_cycle);

% ======================= AUTOMATED CRITERIA =============================
LiqCriteria = struct();

% ---- SA (point-wise gamma) ----
idx_SA = find(abs(gamma) >= config.criteria.gamma_SA, 1, 'first');
if isempty(idx_SA)
    [~, idx_SA] = max(abs(gamma));
    LiqCriteria.SA.threshold_used = abs(gamma(idx_SA));
    LiqCriteria.SA.triggered = false;
else
    LiqCriteria.SA.threshold_used = config.criteria.gamma_SA;
    LiqCriteria.SA.triggered = true;
end
LiqCriteria.SA.N_L      = FCN(idx_SA);
LiqCriteria.SA.idx_data = idx_SA;
LiqCriteria.SA.W        = W_running(idx_SA);

% ---- DA (double amplitude, interpolated between cycles) ----
% Each cycle contributes one point: its gamma_DA (peak-to-peak strain of
% the closed loop) and the cumulative energy W at the end of that cycle.
% The series starts at N = 0, gamma_DA = 0, W = 0. Between the last cycle
% below the threshold and the first cycle at or above it, N, W (and its
% positive / negative parts) are interpolated LINEARLY IN gamma_DA, so
% N_L_DA and W_DA are the values at gamma_DA = threshold exactly (Fig08).
thrDA   = config.criteria.gamma_DA;
DA_0    = [0; gamma_DA];
W_DA_0  = [0; W_cumulative_trapz];
Wp_DA_0 = [0; cumsum(W_pos_cycle)];
Wm_DA_0 = [0; cumsum(W_neg_cycle)];
cDA     = find(gamma_DA >= thrDA, 1, 'first');
if isempty(cDA)
    [maxDA, cMax] = max(gamma_DA);
    N_DA = cMax;
    W_at_DA = NaN;  Wpos_at_DA = NaN;  Wneg_at_DA = NaN;
    DA_before = NaN;  DA_after = NaN;
    LiqCriteria.DA.threshold_used = maxDA;
    LiqCriteria.DA.triggered = false;
else
    j          = cDA + 1;                  % row of cycle cDA in the *_0 series
    frac_DA    = (thrDA - DA_0(j-1)) / (DA_0(j) - DA_0(j-1));
    N_DA       = (cDA - 1) + frac_DA;
    W_at_DA    = W_DA_0(j-1)  + frac_DA * (W_DA_0(j)  - W_DA_0(j-1));
    Wpos_at_DA = Wp_DA_0(j-1) + frac_DA * (Wp_DA_0(j) - Wp_DA_0(j-1));
    Wneg_at_DA = Wm_DA_0(j-1) + frac_DA * (Wm_DA_0(j) - Wm_DA_0(j-1));
    DA_before  = DA_0(j-1);
    DA_after   = DA_0(j);
    LiqCriteria.DA.threshold_used = thrDA;
    LiqCriteria.DA.triggered = true;
end
Wn_at_DA = W_at_DA / sigma_v0_Pa;
idx_DA = find(FCN >= N_DA, 1, 'first');
if isempty(idx_DA), idx_DA = nPoints; end
LiqCriteria.DA.N_L      = N_DA;
LiqCriteria.DA.idx_data = idx_DA;
LiqCriteria.DA.W        = W_at_DA;
LiqCriteria.DA.Wpos     = Wpos_at_DA;
LiqCriteria.DA.Wneg     = Wneg_at_DA;

% ---- Ru (measured R_u(t)) ----
% First sample at which the measured R_u reaches the threshold.
idx_Ru = find(Ru >= config.criteria.Ru, 1, 'first');
if isempty(idx_Ru)
    [~, idx_Ru] = max(Ru);
    LiqCriteria.Ru.threshold_used = Ru(idx_Ru);
    LiqCriteria.Ru.triggered = false;
else
    LiqCriteria.Ru.threshold_used = config.criteria.Ru;
    LiqCriteria.Ru.triggered = true;
end
LiqCriteria.Ru.N_L      = FCN(idx_Ru);
LiqCriteria.Ru.idx_data = idx_Ru;
LiqCriteria.Ru.W        = W_running(idx_Ru);

% ---- Stiffness (G/G1, interpolated between cycles) ----
% G/G1 is a per-cycle value at the end of each cycle (G/G1 = 1 at cycle 1).
% As for DA, N, W and its positive / negative parts are interpolated
% linearly in G/G1 between the last cycle above the threshold and the
% first cycle at or below it, so W is the value at G/G1 = threshold.
thrG = config.criteria.G_ratio;
cG   = find(G_ratio <= thrG, 1, 'first');
Wp_cum = cumsum(W_pos_cycle);
Wm_cum = cumsum(W_neg_cycle);
if isempty(cG)
    [~, cMin] = min(G_ratio);
    if isempty(cMin) || ~isfinite(cMin), cMin = nCompleteCycles; end
    N_G = cMin;
    W_at_G = NaN;  Wpos_at_G = NaN;  Wneg_at_G = NaN;
    LiqCriteria.Stiff.threshold_used = G_ratio(cMin);
    LiqCriteria.Stiff.triggered = false;
elseif cG == 1 || ~isfinite(G_ratio(cG-1))
    N_G = cG;
    W_at_G    = W_cumulative_trapz(cG);
    Wpos_at_G = Wp_cum(cG);
    Wneg_at_G = Wm_cum(cG);
    LiqCriteria.Stiff.threshold_used = thrG;
    LiqCriteria.Stiff.triggered = true;
else
    frac_G    = (G_ratio(cG-1) - thrG) / (G_ratio(cG-1) - G_ratio(cG));
    N_G       = (cG - 1) + frac_G;
    W_at_G    = W_cumulative_trapz(cG-1) + frac_G * W_cycle_trapz(cG);
    Wpos_at_G = Wp_cum(cG-1) + frac_G * W_pos_cycle(cG);
    Wneg_at_G = Wm_cum(cG-1) + frac_G * W_neg_cycle(cG);
    LiqCriteria.Stiff.threshold_used = thrG;
    LiqCriteria.Stiff.triggered = true;
end
idx_G = find(FCN >= N_G, 1, 'first');
if isempty(idx_G), idx_G = nPoints; end
LiqCriteria.Stiff.N_L      = N_G;
LiqCriteria.Stiff.idx_data = idx_G;
LiqCriteria.Stiff.W        = W_at_G;
LiqCriteria.Stiff.Wpos     = Wpos_at_G;
LiqCriteria.Stiff.Wneg     = Wneg_at_G;

% ======================= EXPERT JUDGMENT ================================
useExpert = ~strcmpi(config.expert.mode, 'off');

if useExpert
    havePick = isKey(expertPicks, spec.fileName);
    switch lower(config.expert.mode)
        case 'interactive', needPick = true;
        case 'stored',      needPick = ~havePick;
        case 'auto'
            needPick = false;
            if ~havePick
                error('liq:expert:missing', ...
                    'No stored expert pick and expert mode is "auto".');
            end
        otherwise, needPick = ~havePick;
    end

    if needPick
        % Everything the selector needs, bundled so the signature stays short.
        % W_running is already cumtrapz(gamma, tau_Pa) at this point in the
        % script, so the energy shown in the readout is the SAME quantity the
        % pipeline later stores as W_at_liq_trapz - not a re-derivation.
        sel = struct();
        sel.testID          = testID;
        sel.time            = time;
        sel.FCN             = FCN;
        sel.Ru              = Ru;
        sel.gamma_pct       = gamma_pct;
        sel.gamma_DA        = gamma_DA;      % per complete cycle, as a fraction
        sel.tau_kPa         = tau_kPa;
        sel.sigma_kPa       = sigma_kPa;
        sel.W_running       = W_running;
        sel.sigma_v0_kPa    = sigma_v0_kPa;
        sel.sigma_v0_Pa     = sigma_v0_Pa;
        sel.CSR             = CSR;
        sel.nCompleteCycles = nCompleteCycles;
        sel.nPoints         = nPoints;

        Nliq_expert = expertPickGUI(sel, LiqCriteria, config);

        if isnan(Nliq_expert)
            error('liq:expert:cancelled', 'Expert selection was cancelled.');
        end
        expertPicks(spec.fileName) = Nliq_expert;
        writeExpertPicks(expertPicks, picksFile);
    else
        Nliq_expert = expertPicks(spec.fileName);
        logf(logFID, '     Expert pick reused: N_L = %.2f\n', Nliq_expert);
    end

    Nliq_expert = max(0.001, min(Nliq_expert, nCompleteCycles));
    idx_expert  = find(FCN >= Nliq_expert, 1, 'first');
    if isempty(idx_expert), idx_expert = nPoints; end

    LiqCriteria.Expert.N_L            = Nliq_expert;
    LiqCriteria.Expert.Ru_selected    = Ru(idx_expert);
    LiqCriteria.Expert.idx_data       = idx_expert;
    LiqCriteria.Expert.triggered      = true;
    LiqCriteria.Expert.threshold_used = Ru(idx_expert);
    LiqCriteria.Expert.W              = W_running(idx_expert);
else
    Nliq_expert = NaN;
    LiqCriteria.Expert.N_L            = NaN;
    LiqCriteria.Expert.Ru_selected    = NaN;
    LiqCriteria.Expert.idx_data       = NaN;
    LiqCriteria.Expert.triggered      = false;
    LiqCriteria.Expert.threshold_used = NaN;
    LiqCriteria.Expert.W              = NaN;
end

% ======================= EVERY CRITERION, AS IF PRIMARY =================
% N_L and the energy W each criterion gives with its own threshold, so the
% unselected criteria can be compared with the primary one. SA, Ru and
% Expert fire at a sample (W = running energy there); DA and Stiffness are
% interpolated between cycles. A criterion that never reached its
% threshold reports NaN (never a fallback value).
critKeys  = {'SA', 'DA', 'Ru', 'Stiff', 'Expert'};
critThr   = [config.criteria.gamma_SA*100, config.criteria.gamma_DA*100, ...
             config.criteria.Ru, config.criteria.G_ratio, NaN];
critUnit  = {'|gamma| %', 'gamma_DA %', 'R_u', 'G/G1', 'manual pick'};
nCrit     = numel(critKeys);
crit_trig = false(nCrit, 1);
crit_N    = nan(nCrit, 1);   crit_W  = nan(nCrit, 1);
crit_Ru   = nan(nCrit, 1);   crit_g  = nan(nCrit, 1);
for i = 1:nCrit
    Ci = LiqCriteria.(critKeys{i});
    crit_trig(i) = Ci.triggered;
    if Ci.triggered
        crit_N(i)  = Ci.N_L;
        crit_W(i)  = Ci.W;
        crit_Ru(i) = Ru(Ci.idx_data);
        crit_g(i)  = gamma_pct(Ci.idx_data);
    end
end
crit_Wn = crit_W / sigma_v0_Pa;

% ======================= PRIMARY CRITERION ==============================
switch upper(config.criteria.primary)
    case 'SA',     Primary = LiqCriteria.SA;    criterionLabel = 'Single Amplitude';
    case 'DA',     Primary = LiqCriteria.DA;    criterionLabel = 'Double Amplitude';
    case 'RU',     Primary = LiqCriteria.Ru;    criterionLabel = 'Pore Pressure Ratio';
    case 'STIFF',  Primary = LiqCriteria.Stiff; criterionLabel = 'Stiffness Degradation';
    case 'EXPERT'
        if useExpert && LiqCriteria.Expert.triggered
            Primary = LiqCriteria.Expert; criterionLabel = 'Expert Judgment';
        else
            error('liq:criteria:expert', ...
                  'EXPERT is the primary criterion but no expert pick is available.');
        end
    otherwise
        Primary = LiqCriteria.DA; criterionLabel = 'Double Amplitude';
end

N_L_used     = Primary.N_L;
idx_data_liq = min(Primary.idx_data, nPoints);
liquefied    = Primary.triggered;

nC_liq = max(1, min(ceil(N_L_used), nCompleteCycles));
idx_data_roundup = cycleEndIdx(nC_liq);
if idx_data_liq > idx_data_roundup
    idx_data_roundup = min(idx_data_liq, nPoints);
end

% ======================= DATA AT LIQUEFACTION ===========================
tau_liq       = tau_kPa(1:idx_data_roundup);
gamma_pct_liq = gamma_pct(1:idx_data_roundup);
sigma_liq     = sigma_kPa(1:idx_data_roundup);
Ru_liq        = Ru(1:idx_data_roundup);
FCN_liq       = FCN(1:idx_data_roundup);

W_at_liq_trapz  = W_running(idx_data_liq);
Wn_at_liq_trapz = W_at_liq_trapz / sigma_v0_Pa;

actual_liq_cycle = max(1, min(floor(N_L_used), nCompleteCycles));

% Positive / negative work taken from the SAME slice as W_at_liq, so that
% W_pos + W_neg equals W_at_liq by construction.
dGamma_all  = diff(gamma(1:idx_data_liq));
tau_avg_all = (tau_Pa(1:idx_data_liq-1) + tau_Pa(2:idx_data_liq)) / 2;
dW_all      = tau_avg_all .* dGamma_all;
W_pos_at_liq = sum(dW_all(dW_all > 0));
W_neg_at_liq = sum(dW_all(dW_all < 0));

% With DA or Stiffness as the primary criterion, the energy at
% liquefaction is the value interpolated between cycles at the threshold;
% W_pos and W_neg are interpolated the same way, so W_pos + W_neg = W.
if isfield(Primary, 'Wpos') && Primary.triggered
    W_at_liq_trapz  = Primary.W;
    Wn_at_liq_trapz = Primary.W / sigma_v0_Pa;
    W_pos_at_liq    = Primary.Wpos;
    W_neg_at_liq    = Primary.Wneg;
end

if W_pos_at_liq > 0
    Energy_recovery_at_liq = abs(W_neg_at_liq) / W_pos_at_liq;
else
    Energy_recovery_at_liq = NaN;
end

Ru_at_liq  = Ru(idx_data_liq);           % measured R_u at liquefaction
CSR_liq    = CSR;
W_specific = W_at_liq_trapz / (sigma_v0_Pa^2);

% Post-liquefaction residual strength
if idx_data_liq < nPoints
    tau_post_liq = tau_kPa(idx_data_liq:end);
    nPost = numel(tau_post_liq);
    if nPost > 10
        tau_res_kPa   = mean(abs(tau_post_liq(max(1,round(0.8*nPost)):end)));
        tau_res_ratio = tau_res_kPa / sigma_v0_kPa;
    else
        tau_res_kPa = NaN; tau_res_ratio = NaN;
    end
else
    tau_res_kPa = NaN; tau_res_ratio = NaN;
end

% R_u,max and R_u,res at liquefaction: read off the same curves Fig03
% draws (the R_u,max envelope and the pchip curve through R_u,res)
Ru_max_at_liq = smoothThrough(envN, envR, N_L_used);     % on the envelope
Ru_res_at_liq = smoothThrough(N_res0, Ru_res_0, N_L_used);

liq_point_gamma = gamma_pct(idx_data_liq);
liq_point_tau   = tau_kPa(idx_data_liq);
cum_abs_gamma_at_liq_pct = cum_abs_gamma_pct(idx_data_liq);

% ======================= RESULT STRUCT ==================================
reportNaN = ~liquefied && strcmpi(config.criteria.onNotTriggered, 'nan');

R.criterionLabel = criterionLabel;
R.liquefied      = liquefied;
R.N_L        = valOrNaN(N_L_used,        reportNaN);
R.W_at_liq   = valOrNaN(W_at_liq_trapz,  reportNaN);
R.Wn_at_liq  = valOrNaN(Wn_at_liq_trapz, reportNaN);
R.Ru_at_liq  = valOrNaN(Ru_at_liq,       reportNaN);
R.W_pos_at_liq = valOrNaN(W_pos_at_liq,  reportNaN);
R.W_neg_at_liq = valOrNaN(W_neg_at_liq,  reportNaN);
R.Energy_recovery_at_liq = valOrNaN(Energy_recovery_at_liq, reportNaN);
R.W_at_DA    = W_at_DA;                  % NaN when DA was never reached
R.Wn_at_DA   = Wn_at_DA;
R.N_L_SA     = crit_N(1);     % NaN when the criterion never fired
R.N_L_DA     = crit_N(2);
R.N_L_Ru     = crit_N(3);
R.N_L_Stiff  = crit_N(4);
R.N_L_Expert = crit_N(5);
R.W_at_SA     = crit_W(1);
R.W_at_Ru     = crit_W(3);
R.W_at_Stiff  = crit_W(4);
R.W_at_Expert = crit_W(5);
R.Ru_max_at_liq = valOrNaN(Ru_max_at_liq, reportNaN);
R.Ru_res_at_liq = valOrNaN(Ru_res_at_liq, reportNaN);
R.tau_res_ratio = tau_res_ratio;
R.cum_abs_gamma_at_liq_pct = cum_abs_gamma_at_liq_pct;

if ~liquefied
    msg = sprintf('%s criterion never reached its threshold', criterionLabel);
    if isempty(R.note), R.note = msg; else, R.note = [R.note '; ' msg]; end
end

% ======================= OUTPUT FILE NAME ===============================
% One base name shared by the Excel workbook and the figure PDF, so the two
% outputs of a test always pair up (only the extension differs).
outBase = sprintf('%s_CSR%.2f_%s_NL%.2f', ...
                  testID, CSR_liq, config.criteria.primary, N_L_used);

% ======================= EXCEL EXPORT ===================================
if config.output.excel

    outFile = fullfile(outputDir, [outBase '.xlsx']);

    Sheet1 = table();
    Sheet1.Cycle          = cycleNumbers;
    Sheet1.tau_max_kPa    = tau_max;
    Sheet1.tau_min_kPa    = tau_min;
    Sheet1.gamma_max      = gamma_max;
    Sheet1.gamma_min      = gamma_min;
    Sheet1.gamma_DA       = gamma_DA;
    Sheet1.gamma_DA_pct   = gamma_DA * 100;
    Sheet1.gamma_cyc      = gamma_cyc;
    Sheet1.gamma_cyc_pct  = gamma_cyc * 100;
    Sheet1.G_sec_kPa      = G_sec_kPa;
    Sheet1.G_sec_MPa      = G_sec_MPa;
    Sheet1.G_ratio        = G_ratio;
    Sheet1.Damping_pct    = D_ratio;
    Sheet1.N_Ru_max_cycle = N_Ru_max_cycle;
    Sheet1.Ru_max_cycle   = Ru_max_cycle;
    Sheet1.Ru_res         = Ru_res_cycle;
    Sheet1.sigma_min_kPa  = sigma_min;
    Sheet1.tau_max_norm   = tau_max_norm;
    Sheet1.tau_min_norm   = tau_min_norm;
    Sheet1.sigma_min_norm = sigma_min_norm;
    Sheet1.sigma_end_kPa  = sigma_end;
    Sheet1.sigma_end_norm = sigma_end_norm;
    Sheet1.W_trapz_Jm3    = W_cycle_trapz;
    Sheet1.W_trapz_cum    = W_cumulative_trapz;
    Sheet1.W_trapz_cum_kJm3 = W_cumulative_trapz / 1000;
    Sheet1.Wn_trapz       = Wn_cycle_trapz;
    Sheet1.Wn_trapz_cum   = Wn_cumulative_trapz;
    Sheet1.Energy_recovery= Energy_recovery_ratio;
    Sheet1.dRu_dN         = dRu_dN;
    Sheet1.dGammaDA_dN    = dGammaDA_dN;
    Sheet1.cum_abs_gamma  = cum_abs_gamma_cycle_total;
    Sheet1.CSR_per_cycle  = CSR_per_cycle;

    Sheet2 = table();
    Sheet2.FCN               = FCN(1:idx_data_liq);
    Sheet2.NN                = floor(FCN(1:idx_data_liq)+1);
    Sheet2.tau_kPa           = tau_kPa(1:idx_data_liq);
    Sheet2.gamma             = gamma(1:idx_data_liq);
    Sheet2.gamma_pct         = gamma_pct(1:idx_data_liq);
    Sheet2.sigma_kPa         = sigma_kPa(1:idx_data_liq);
    Sheet2.Ru                = Ru(1:idx_data_liq);
    Sheet2.sigma_norm        = sigma_norm(1:idx_data_liq);
    Sheet2.tau_norm          = tau_norm(1:idx_data_liq);
    Sheet2.W_running         = W_running(1:idx_data_liq);
    Sheet2.W_running_norm    = W_running_norm(1:idx_data_liq);
    Sheet2.epsilon_v_pct     = epsilon_v_pct(1:idx_data_liq);
    Sheet2.cum_abs_gamma_pct = cum_abs_gamma_pct(1:idx_data_liq);

    Sheet3 = table();
    Sheet3.FCN               = FCN;
    Sheet3.tau_kPa           = tau_kPa;
    Sheet3.gamma             = gamma;
    Sheet3.gamma_pct         = gamma_pct;
    Sheet3.sigma_kPa         = sigma_kPa;
    Sheet3.Ru                = Ru;
    Sheet3.sigma_norm        = sigma_norm;
    Sheet3.tau_norm          = tau_norm;
    Sheet3.W_running         = W_running;
    Sheet3.W_running_norm    = W_running_norm;
    Sheet3.epsilon_v_pct     = epsilon_v_pct;
    Sheet3.cum_abs_gamma_pct = cum_abs_gamma_pct;

    % R_u,res per cycle, starting at N = 0, R_u = 0
    SheetRes = table(N_res0, Ru_res_0, 'VariableNames', {'Cycle','Ru_res'});

    % R_u,max per cycle, with the N, time and sample where it occurs
    SheetMax = table(cyc_RuMax, N_RuMax, time(idx_RuMax), idx_RuMax, Ru_max, ...
                     'VariableNames', {'Cycle','N','time_s','sample','Ru_max'});

    % Points the R_u,max envelope passes through
    envType = repmat({'support'}, numel(envN), 1);
    envType(envIsPeak) = {'R_u,max'};
    envType(1)         = {'origin'};
    SheetEnv = table(envN, envR, envType, 'VariableNames', {'N','Ru','PointType'});

    C1 = AC_complete{1};
    Sheet4 = table();
    Sheet4.gamma_C1   = C1(:, 7);
    Sheet4.tau_kPa_C1 = C1(:, 6);
    Sheet4.tau_MPa_C1 = C1(:, 6) / 1000;

    summaryData = {
        'Parameter', 'Value', 'Unit';
        'fileName', testID, '-';
        'sand', spec.sand, '-';
        'treatment', spec.treatment, '-';
        'finesContent', spec.FC_pct, '%';
        'sigma_v0_kPa', sigma_v0_kPa, 'kPa';
        'CSR', CSR_liq, '-';
        'CSR_method', sprintf('mean of first %d cycles', nCSR_cycles), '-';
        'H0', H_0, 'mm';
        'Hps', H_ps, 'mm';
        'deltaH', deltaH, 'mm';
        'e0', e_0, '-';
        'e_ps', e_ps, '-';
        'delta_e', delta_e, '-';
        'G_sec_cycle1_MPa', R.G_sec1_MPa, 'MPa';
        'primaryCriterion', criterionLabel, '-';
        'liquefied', ternary(liquefied,'yes','no'), '-';
        'N_L', R.N_L, 'cycles';
        'N_L_SA', crit_N(1), 'cycles';
        'W_at_SA_Jm3', crit_W(1), 'J/m3';
        'N_L_DA', crit_N(2), 'cycles';
        'W_at_DA_Jm3', crit_W(2), 'J/m3';
        'N_L_Ru', crit_N(3), 'cycles';
        'W_at_Ru_Jm3', crit_W(3), 'J/m3';
        'N_L_Stiff', crit_N(4), 'cycles';
        'W_at_Stiff_Jm3', crit_W(4), 'J/m3';
        'N_L_Expert', crit_N(5), 'cycles';
        'W_at_Expert_Jm3', crit_W(5), 'J/m3';
        'Ru_at_Expert', LiqCriteria.Expert.Ru_selected, '-';
        'threshold_SA', config.criteria.gamma_SA * 100, '%';
        'threshold_DA', config.criteria.gamma_DA * 100, '%';
        'threshold_Ru', config.criteria.Ru, '-';
        'threshold_G_ratio', config.criteria.G_ratio, '-';
        'W_at_liq_trapz_Jm3', W_at_liq_trapz, 'J/m3';
        'W_at_liq_trapz_kJm3', W_at_liq_trapz/1000, 'kJ/m3';
        'Wn_at_liq_trapz', Wn_at_liq_trapz, '-';
        'W_pos_at_liq_Jm3', W_pos_at_liq, 'J/m3';
        'W_neg_at_liq_Jm3', W_neg_at_liq, 'J/m3';
        'Energy_recovery_at_liq', Energy_recovery_at_liq, '-';
        'W_specific_capacity', W_specific, '1/Pa';
        'Wn_at_DA', Wn_at_DA, '-';
        'gamma_DA_cycle_before_pct', DA_before * 100, '%';
        'gamma_DA_cycle_after_pct', DA_after * 100, '%';
        'Ru_at_liq', Ru_at_liq, '-';
        'Ru_max_at_liq', Ru_max_at_liq, '-';
        'Ru_res_at_liq', Ru_res_at_liq, '-';
        'gamma_DA_at_liq_pct', gamma_DA(actual_liq_cycle)*100, '%';
        'cum_abs_gamma_at_liq_pct', cum_abs_gamma_at_liq_pct, '%';
        'tau_res_kPa', tau_res_kPa, 'kPa';
        'tau_res_ratio', tau_res_ratio, '-';
        'nCompleteCycles', nCompleteCycles, '-';
        'actual_liq_cycle_floor', actual_liq_cycle, '-';
        'nC_liq_roundup', nC_liq, '-';
        'liq_point_gamma_pct', liq_point_gamma, '%';
        'liq_point_tau_kPa', liq_point_tau, 'kPa';
        'expertJudgment_used', ternary(useExpert,'yes','no'), '-';
        'epsilon_v_max_pct', R.epsilon_v_max_pct, '%';
        };
    Sheet5 = cell2table(summaryData(2:end,:), 'VariableNames', summaryData(1,:));

    Sheet6 = table(CSR_liq, crit_N(1), crit_N(2), crit_N(3), crit_N(4), ...
        crit_N(5), Ru_at_liq, Ru_max_at_liq, Ru_res_at_liq, ...
        W_at_liq_trapz, Wn_at_liq_trapz, crit_W(1), crit_W(2), crit_W(3), ...
        crit_W(4), crit_W(5), deltaH, e_ps, R.G_sec1_MPa, ...
        'VariableNames', {'CSR','N_L_SA','N_L_DA','N_L_Ru','N_L_Stiff', ...
                          'N_L_Expert','Ru_at_liq','Ru_max_at_liq','Ru_res_at_liq','W_trapz', ...
                          'Wn_trapz','W_at_SA','W_at_DA','W_at_Ru','W_at_Stiff', ...
                          'W_at_Expert','dH_mm','e_ps','Gsec1_MPa'});

    % Every criterion with its own threshold, as if it were the primary one
    isPrim = strcmpi(critKeys(:), config.criteria.primary);
    SheetCrit = table(critKeys(:), cellfun(@(b) ternary(b,'yes','no'), num2cell(isPrim), ...
                      'UniformOutput', false), critThr(:), critUnit(:), ...
                      cellfun(@(b) ternary(b,'yes','no'), num2cell(crit_trig), ...
                      'UniformOutput', false), crit_N, crit_W, crit_Wn, crit_Ru, crit_g, ...
        'VariableNames', {'Criterion','Primary','Threshold','ThresholdUnit', ...
                          'Triggered','N_L','W_Jm3','Wn','Ru_at_N_L','gamma_pct_at_N_L'});

    warning('off', 'MATLAB:xlswrite:AddSheet');
    if isfile(outFile), delete(outFile); end
    writetable(Sheet1, outFile, 'Sheet', 'CycleData');
    writetable(SheetRes, outFile, 'Sheet', 'Ru_res');
    writetable(SheetMax, outFile, 'Sheet', 'Ru_max');
    writetable(SheetEnv, outFile, 'Sheet', 'Ru_max_envelope');
    writetable(Sheet2, outFile, 'Sheet', 'TimeSeries_ToLiq');
    writetable(Sheet3, outFile, 'Sheet', 'TimeSeries_Full');
    writetable(Sheet4, outFile, 'Sheet', 'FirstCycle');
    writetable(Sheet5, outFile, 'Sheet', 'Summary');
    writetable(Sheet6, outFile, 'Sheet', 'Summary2');
    writetable(SheetCrit, outFile, 'Sheet', 'Criteria');

    % Per-cycle workbook
    if config.output.perCycleSheets
        cycleFile = fullfile(outputDir, [outBase '_CycleData.xlsx']);
        if isfile(cycleFile), delete(cycleFile); end
        for c = 1:nCompleteCycles
            cd_ = AC_complete{c};
            T = table();
            T.time_s       = cd_(:, 1);
            T.sigma_kPa    = cd_(:, 9);
            T.sigma_norm   = cd_(:, 9) ./ sigma_v0_kPa;
            T.tau_kPa      = cd_(:, 6);
            T.tau_norm     = cd_(:, 6) ./ sigma_v0_kPa;
            T.gamma        = cd_(:, 7);
            T.gamma_pct    = cd_(:, 8);
            T.W_within_Jm3 = W_within_cycles{c};
            writetable(T, cycleFile, 'Sheet', sprintf('Cycle_%02d', c));
        end
    end
end

% ======================= FIGURES (invisible, saved to PDF) ==============
if config.output.figures

    colors = struct('blue','#0072BD', 'orange','#D95319', 'green','#77AC30', ...
                    'purple','#7E2F8E', 'teal','#008080', 'red','#A2142F', ...
                    'cyan','#4DBEEE', 'gray',[0.5 0.5 0.5]);
    figs = gobjects(0);
    FN = config.output.font;

    % Colour ramp, grey -> red, one colour per cycle
    grayToRed = grayRedRamp(nC_liq);
    cbLim = [1 max(2, nC_liq)];   % clim requires increasing limits

    % ---- FIG 1: overview ----
    figs(end+1) = newFigure('Fig01_Overview');
    subplot(2,2,1)
    plot(FCN_liq, Ru_liq, 'Color', colors.blue, 'LineWidth', 1); hold on
    xlabel('Number of Load Cycles, N_c','FontSize',14,'FontName',FN)
    ylabel('Excess Pore Pressure Ratio, R_u','FontSize',14,'FontName',FN)
    legend(['R_u = ' num2str(Ru_at_liq,'%.2f')], 'Location','southeast','Box','off')
    title([criterionLabel ' Criterion'],'FontSize',14); grid on; ylim([0 1.05])

    subplot(2,2,2)
    plot(sigma_liq, tau_liq, 'Color', colors.teal, 'LineWidth', 1.5); hold on
    yline(0, ':k')
    xlabel('\sigma''_v (kPa)','FontSize',14,'FontName',FN)
    ylabel('\tau (kPa)','FontSize',14,'FontName',FN)
    title(['CSR = ' num2str(CSR_liq,'%.3f')],'FontSize',14); grid on

    subplot(2,2,3)
    plot(FCN_liq, gamma_pct_liq, 'Color', colors.purple, 'LineWidth', 1.5); hold on
    yline(config.criteria.gamma_SA*100, '--r', 'LineWidth', 1.5)
    yline(-config.criteria.gamma_SA*100, '--r', 'LineWidth', 1.5)
    yline(0, ':k')
    xlabel('Number of Load Cycles, N_c','FontSize',14,'FontName',FN)
    ylabel('Shear Strain, \gamma (%)','FontSize',14,'FontName',FN)
    title(['N_L = ' num2str(N_L_used,'%.2f')],'FontSize',14)
    ylim('padded'); grid on

    subplot(2,2,4)
    plot(gamma_pct_liq, tau_liq, 'Color', colors.red, 'LineWidth', 1.5); hold on
    xline(0, ':k'); yline(0, ':k')
    xlabel('\gamma (%)','FontSize',14,'FontName',FN)
    ylabel('\tau (kPa)','FontSize',14,'FontName',FN)
    title(['\DeltaW = ' num2str(W_at_liq_trapz,'%.1f') ' J/m^3 (cumtrapz)'],'FontSize',14)
    grid on

    sgtitle(sprintf('%s | %s | e_0=%.3f | e_{ps}=%.3f | N_L=%.2f', ...
            texSafe(testID), spec.treatment, e_0, e_ps, N_L_used), ...
            'FontSize',14,'FontWeight','bold')

    % ---- FIG 2: coloured loops ----
    figs(end+1) = newFigure('Fig02_ColoredLoops');
    hold on
    for c = 1:nC_liq
        cd_ = AC_complete{c};
        plot(cd_(:,8), cd_(:,6), 'Color', grayToRed(c,:), 'LineWidth', 1.2)
    end
    plot(liq_point_gamma, liq_point_tau, 'bp', 'MarkerSize', 18, ...
         'MarkerFaceColor', 'b', 'LineWidth', 2)
    xline(0, ':k'); yline(0, ':k')
    xlabel('\gamma (%)','FontSize',16,'FontName',FN)
    ylabel('\tau (kPa)','FontSize',16,'FontName',FN)
    title(sprintf('Stress-Strain Loops (Cycles 1-%d) | N_L = %.4f | W = %.1f J/m^3', ...
          nC_liq, N_L_used, W_at_liq_trapz),'FontSize',14)
    colormap(gca, grayToRed); cb = colorbar; cb.Label.String = 'Cycle'; clim(cbLim)
    grid on; hold off

    % ---- FIG 3: pore pressure generation ----
    % R_u(t) up to N_L + 2, each cycle in its own colour (grey -> red ramp,
    % as in Fig02). R_u,max: filled red triangles (half-cycle maxima) with
    % the upper envelope through them; R_u,res: hollow blue circles (from
    % N = 0) with a smooth curve through them.
    figs(end+1) = newFigure('Fig03_PorePressure');
    COL_RES = '#0072BD';
    COL_MAX = '#D62728';
    N_show  = N_L_used + 2;
    nShow   = max(1, ceil(N_show));
    rampPP  = grayRedRamp(nShow);
    segStart = [cycStart; cycleEndIdx(end)];    % last segment = unfinished cycle
    segEnd   = [cycleEndIdx; nPoints];
    hold on
    for c = 1:min(nShow, numel(segStart))
        ii = segStart(c):segEnd(c);
        ii = ii(FCN(ii) <= N_show);
        if numel(ii) > 1
            plot(FCN(ii), Ru(ii), '-', 'Color', rampPP(c,:), 'LineWidth', 1.1);
        end
    end
    inRes = N_res0 <= N_show;
    xq    = linspace(0, max(N_res0(inRes)), 400);
    hLeg  = gobjects(0);                       % lines and an xline handle
    hLeg(end+1) = plot(xq, smoothThrough(N_res0, Ru_res_0, xq), '-', ...
                       'Color', COL_RES, 'LineWidth', 1.6);
    legTxt = {'R_{u,res} curve'};
    xq = linspace(0, min(N_show, envN(end)), 600);
    hLeg(end+1) = plot(xq, smoothThrough(envN, envR, xq), '-', ...
                       'Color', COL_MAX, 'LineWidth', 1.6);
    legTxt{end+1} = 'R_{u,max} envelope';
    hLeg(end+1) = plot(N_res0(inRes), Ru_res_0(inRes), 'o', 'Color', COL_RES, ...
                       'MarkerFaceColor', 'w', 'MarkerSize', 7, 'LineWidth', 1.5);
    legTxt{end+1} = 'R_{u,res}';
    inPk = N_RuMax <= N_show;
    hLeg(end+1) = plot(N_RuMax(inPk), Ru_max(inPk), '^', 'MarkerEdgeColor', 'k', ...
                       'MarkerFaceColor', COL_MAX, 'MarkerSize', 7, 'LineWidth', 0.5);
    legTxt{end+1} = 'R_{u,max} (half-cycle maxima)';
    hLeg(end+1) = xline(N_L_used, 'k--', 'LineWidth', 1);
    legTxt{end+1} = sprintf('N_L = %.2f', N_L_used);
    xlabel('Number of Load Cycles, N_c','FontSize',14,'FontName',FN)
    ylabel('Excess Pore Pressure Ratio, R_u','FontSize',14,'FontName',FN)
    legend(hLeg, legTxt, 'Location','southeast','Box','off')
    title(sprintf('%s Criterion | N_L = %.2f', criterionLabel, N_L_used),'FontSize',14)
    colormap(gca, rampPP); cb = colorbar; cb.Label.String = 'Cycle';
    clim([0.5 nShow + 0.5]); cb.Ticks = 1:nShow;
    xlim([0 max(N_show, eps)]); ylim([0 1.05]); grid on; hold off

    % ---- FIG 5: semi-log gamma_DA ----
    figs(end+1) = newFigure('Fig05_SemiLog_GammaDA');
    semilogx(cycleNumbers(1:nC_liq), gamma_DA(1:nC_liq)*100, 's-', ...
             'Color', colors.green, 'LineWidth', 1.5, 'MarkerSize', 6, ...
             'MarkerFaceColor', colors.green); hold on
    yline(config.criteria.gamma_DA*100, '--r', 'LineWidth', 1.5)
    xline(max(N_L_used, eps), 'r-', 'LineWidth', 2)
    xlabel('Number of Load Cycles, N_c (log scale)','FontSize',14,'FontName',FN)
    ylabel('\gamma_{DA} (%)','FontSize',14,'FontName',FN)
    title(sprintf('%s | CSR=%.3f | \\sigma''_{v0}=%.1f kPa | \\gamma_{DA} vs N | N_L = %.2f', ...
          texSafe(testID), CSR_liq, sigma_v0_kPa, N_L_used),'FontSize',14)
    grid on

    % ---- FIG 6: G/G1 and damping ----
    figs(end+1) = newFigure('Fig06_G_D_vs_Gamma');
    yyaxis left
    plot(gamma_cyc(1:nC_liq)*100, G_ratio(1:nC_liq), 'o-', 'Color', colors.blue, ...
         'LineWidth', 1.5, 'MarkerSize', 6, 'MarkerFaceColor', colors.blue)
    ylabel('G / G_1','FontSize',14,'FontName',FN); ylim([0 1.1])
    yyaxis right
    plot(gamma_cyc(1:nC_liq)*100, D_ratio(1:nC_liq), 's-', 'Color', colors.red, ...
         'LineWidth', 1.5, 'MarkerSize', 6, 'MarkerFaceColor', colors.red)
    ylabel('Damping Ratio, D (%)','FontSize',14,'FontName',FN)
    xlabel('Cyclic Shear Strain, \gamma_{cyc} (%)','FontSize',14,'FontName',FN)
    title(sprintf('Modulus Reduction & Damping | G_1 = %.2f MPa', R.G_sec1_MPa),'FontSize',14)
    legend('G/G_1','Damping (%)','Location','east'); grid on

    % ---- FIG 7: energy ----
    figs(end+1) = newFigure('Fig07_Energy');
    subplot(2,2,1)
    bar(1:nC_liq, W_cycle_trapz(1:nC_liq), 'FaceColor', colors.blue)
    xlabel('Cycle','FontSize',14); ylabel('W (J/m^3)','FontSize',14)
    title('Energy per Cycle','FontSize',14); grid on

    subplot(2,2,2)
    plot(1:nC_liq, W_cumulative_trapz(1:nC_liq), 'o-', 'Color', colors.blue, ...
         'LineWidth', 1.5, 'MarkerSize', 5); hold on
    xline(N_L_used, 'r-', 'LineWidth', 2)
    plot(N_L_used, W_at_liq_trapz, 'rp', 'MarkerSize', 15, 'MarkerFaceColor', 'r')
    xlabel('Cycle','FontSize',14); ylabel('\SigmaW (J/m^3)','FontSize',14)
    title(sprintf('Cumulative: %.1f J/m^3 @ N_L=%.2f', W_at_liq_trapz, N_L_used),'FontSize',14)
    grid on

    subplot(2,2,3)
    bar(1:nC_liq, Wn_cycle_trapz(1:nC_liq), 'FaceColor', colors.cyan)
    xlabel('Cycle','FontSize',14); ylabel('W_n','FontSize',14)
    title('Normalized Energy per Cycle','FontSize',14); grid on

    subplot(2,2,4)
    plot(1:nC_liq, Wn_cumulative_trapz(1:nC_liq), 'o-', 'Color', colors.orange, ...
         'LineWidth', 1.5, 'MarkerSize', 5); hold on
    xline(N_L_used, 'r-', 'LineWidth', 2)
    plot(N_L_used, Wn_at_liq_trapz, 'rp', 'MarkerSize', 15, 'MarkerFaceColor', 'r')
    xlabel('Cycle','FontSize',14); ylabel('\SigmaW_n','FontSize',14)
    title(sprintf('Cumulative W_n: %.6f @ N_L=%.2f', Wn_at_liq_trapz, N_L_used),'FontSize',14)
    grid on
    sgtitle(sprintf('Energy Analysis (cumtrapz) | W at N_L = %.1f J/m^3 (sample %d)', ...
            W_at_liq_trapz, idx_data_liq), 'FontSize',14,'FontWeight','bold')

    % ---- FIG 8: energy vs double-amplitude strain ----
    % One point per cycle: cumulative energy at the end of the cycle vs that
    % cycle's gamma_DA, starting at (0, 0). The straight segments are the
    % linear interpolation used for N_L_DA and W_DA; the star marks W at
    % gamma_DA = threshold.
    figs(end+1) = newFigure('Fig08_W_vs_GammaDA');
    plot(DA_0*100, W_DA_0, 'o-', 'Color', colors.blue, 'LineWidth', 1.5, ...
         'MarkerSize', 6, 'MarkerFaceColor', colors.blue); hold on
    xline(thrDA*100, '--r', 'LineWidth', 1.5)
    if LiqCriteria.DA.triggered
        plot(thrDA*100, W_at_DA, 'rp', 'MarkerSize', 18, 'MarkerFaceColor', 'r')
        legend('Cycle ends (from 0)', sprintf('\\gamma_{DA} = %.2f%%', thrDA*100), ...
               sprintf('W = %.1f J/m^3 at N = %.3f', W_at_DA, N_DA), ...
               'Location','northwest','Box','off')
        title(sprintf('Energy at \\gamma_{DA} = %.2f%%: %.1f J/m^3 (W_n = %.5f)', ...
              thrDA*100, W_at_DA, Wn_at_DA),'FontSize',14)
    else
        legend('Cycle ends (from 0)', sprintf('\\gamma_{DA} = %.2f%%', thrDA*100), ...
               'Location','northwest','Box','off')
        title(sprintf('\\gamma_{DA} = %.2f%% not reached (max %.2f%%)', ...
              thrDA*100, max(gamma_DA)*100),'FontSize',14)
    end
    xlabel('Double-Amplitude Shear Strain, \gamma_{DA} (%)','FontSize',14,'FontName',FN)
    ylabel('Cumulative Dissipated Energy, W (J/m^3)','FontSize',14,'FontName',FN)
    grid on; hold off

    % ---- FIG 14: dynamic properties ----
    figs(end+1) = newFigure('Fig14_DynamicProps');
    subplot(2,2,1)
    plot(cycleNumbers, G_sec_MPa, 'o-', 'Color', colors.blue, ...
         'LineWidth', 1.5, 'MarkerSize', 5)
    xlabel('Cycle','FontSize',12); ylabel('G_{sec} (MPa)','FontSize',12)
    title('Secant Modulus (ASTM D8296-19)','FontSize',12); grid on

    subplot(2,2,2)
    plot(cycleNumbers, G_ratio, 'o-', 'Color', colors.orange, ...
         'LineWidth', 1.5, 'MarkerSize', 5); hold on
    yline(config.criteria.G_ratio, '--r', 'LineWidth', 1.5)
    xlabel('Cycle','FontSize',12); ylabel('G/G_1','FontSize',12)
    title('Stiffness Degradation','FontSize',12); grid on

    subplot(2,2,3)
    plot(gamma_cyc*100, G_sec_MPa, 'o-', 'Color', colors.purple, ...
         'LineWidth', 1.5, 'MarkerSize', 5)
    xlabel('\gamma_{cyc} (%)','FontSize',12); ylabel('G_{sec} (MPa)','FontSize',12)
    title('Modulus Reduction','FontSize',12); grid on

    subplot(2,2,4)
    plot(gamma_cyc*100, D_ratio, 'o-', 'Color', colors.red, ...
         'LineWidth', 1.5, 'MarkerSize', 5)
    xlabel('\gamma_{cyc} (%)','FontSize',12); ylabel('D (%)','FontSize',12)
    title('Damping Ratio vs Strain','FontSize',12); grid on
    sgtitle(sprintf('Dynamic Properties | G_1 = %.2f MPa', R.G_sec1_MPa), ...
            'FontSize',14,'FontWeight','bold')

    % ---- FIG 19: residual excess pore pressure ratio ----
    % R_u,max (half-cycle maxima, each at its own N) vs R_u,res (final
    % point of each cycle), both starting at N = 0, R_u = 0.
    figs(end+1) = newFigure('Fig19_ResidualRu');
    n0 = nC_liq + 1;                     % cycles 0..nC_liq in the *_0 series

    subplot(1,2,1)
    inPk19 = N_max0 <= nC_liq;
    plot(N_max0(inPk19), Ru_max_0(inPk19), '^-', ...
         'Color', colors.gray, 'LineWidth', 1, 'MarkerSize', 4); hold on
    plot(N_res0(1:n0), Ru_res_0(1:n0), 's-', ...
         'Color', colors.red, 'LineWidth', 1.8, 'MarkerSize', 6, ...
         'MarkerFaceColor', colors.red)
    xline(N_L_used, 'k--', 'LineWidth', 1.5)
    plot(N_L_used, Ru_res_at_liq, 'bp', 'MarkerSize', 15, 'MarkerFaceColor', 'b')
    xlabel('Number of Load Cycles, N_c','FontSize',13,'FontName',FN)
    ylabel('R_u','FontSize',13,'FontName',FN)
    legend('R_{u,max} (half-cycle maxima)','R_{u,res} (final point of cycle)', ...
           'N_L','Location','southeast','Box','off')
    title('R_{u,max} vs. R_{u,res}','FontSize',13); grid on; ylim([0 1.05])

    subplot(1,2,2)
    plot([0; Wn_cumulative_trapz(1:nC_liq)], Ru_res_0(1:n0), 'o', ...
         'Color', colors.red, 'MarkerFaceColor', colors.red, 'MarkerSize', 7); hold on
    xline(Wn_at_liq_trapz, ':k', 'LineWidth', 1.5)
    plot(Wn_at_liq_trapz, Ru_res_at_liq, 'bp', 'MarkerSize', 15, 'MarkerFaceColor', 'b')
    xlabel('Normalized Cumulative Energy, W_n','FontSize',13,'FontName',FN)
    ylabel('R_{u,res}','FontSize',13,'FontName',FN)
    title('R_{u,res} vs. Dissipated Energy','FontSize',13); grid on; ylim([0 1.05])

    sgtitle(sprintf('%s | Residual Excess Pore Pressure Ratio | R_{u,res} at N_L = %.2f', ...
            texSafe(testID), Ru_res_at_liq),'FontSize',14,'FontWeight','bold')

    % ---- export and close ----
    pdfName = fullfile(outputDir, [outBase '.pdf']);
    if isfile(pdfName), delete(pdfName); end
    for f = 1:numel(figs)
        if isvalid(figs(f))
            exportgraphics(figs(f), pdfName, 'ContentType', 'vector', 'Append', f > 1);
        end
    end
    close(figs(isvalid(figs)));
end

end % analyzeOneFile


%% =========================================================================
%  EXPERT SELECTION
%  =========================================================================

function N_L = expertPickGUI(sel, LiqCriteria, config)
%EXPERTPICKGUI  Slider-driven selection of the liquefaction point N_L.
%
%   Four panels mirroring Fig01_Overview, each showing the FULL shear record
%   in grey. Two coupled sliders (integer cycle + fraction within the cycle)
%   drive a red guide line and marker across all four panels, with the record
%   up to the selected point drawn as a coloured overlay.
%
%   INDEX MAPPING.  The selected point is
%       N   = (c - 1) + f,  clamped to [0.001, nCompleteCycles]
%       idx = find(FCN >= N, 1, 'first')
%   which is exactly the mapping analyzeOneFile applies to the returned value.
%   FCN comes from the measured tau = 0 cycle boundaries, so no fixed period
%   or sampling interval is assumed and unequal cycle lengths are handled
%   correctly.
%
%   ENERGY.  W = cumtrapz(gamma, tau_Pa) evaluated at idx, i.e. the cumulative
%   dissipated work per unit volume int(tau dgamma) in J/m^3, plus the
%   stress-normalized Wn = W / sigma_v0[Pa]. Identical to W_at_liq_trapz and
%   Wn_at_liq_trapz downstream.
%
%   Returns NaN if the window is closed or Cancel is pressed - the caller
%   turns that into liq:expert:cancelled, as before.

N_L = NaN;

% ---------------------------------------------------------------- data ----
testID = sel.testID;
FCN    = sel.FCN(:);
Ru     = sel.Ru(:);
g_pct  = sel.gamma_pct(:);
gDA    = sel.gamma_DA(:);          % per-cycle peak-to-peak strain
tau    = sel.tau_kPa(:);
sig    = sel.sigma_kPa(:);
W_run  = sel.W_running(:);
tsec   = sel.time(:);
nC     = sel.nCompleteCycles;
nPts   = sel.nPoints;
sv0    = sel.sigma_v0_kPa;
sv0Pa  = sel.sigma_v0_Pa;

FN     = config.output.font;
SA_pct = config.criteria.gamma_SA * 100;
DA_pct = config.criteria.gamma_DA * 100;

% ------------------------------------------------------- starting guess ---
% Seeded from the automated criteria so the sliders open somewhere sensible.
N0 = NaN;
if isfield(LiqCriteria,'Ru') && LiqCriteria.Ru.triggered, N0 = LiqCriteria.Ru.N_L; end
if ~isfinite(N0) && LiqCriteria.DA.triggered,             N0 = LiqCriteria.DA.N_L; end
if ~isfinite(N0),                                         N0 = nC/2;              end
N0 = max(0, min(N0, nC));
c0 = floor(N0) + 1;
f0 = N0 - floor(N0);
if c0 > nC, c0 = nC; f0 = 1; end
c0 = max(1, c0);

% --------------------------------------------------- change point detect --
% Signal Processing Toolbox; its absence must not be fatal.
CH_Ru = [];
if config.expert.changePoints
    try
        CH_Ru = FCN(findchangepts(Ru, 'Statistic', 'linear', ...
                                  'MaxNumChanges', config.expert.maxChangePoints));
    catch, CH_Ru = [];
    end
end

% ================================ LAYOUT ==================================
fig = uifigure('Name', ['Expert selection - ' char(testID)], ...
               'Color', 'w', 'Position', [60 60 1320 860]);
fig.CloseRequestFcn = @(~,~) onCancel();

gl = uigridlayout(fig, [4 1]);
gl.RowHeight   = {26, '1x', 150, 40};   % tall enough for the 8-line readout
gl.ColumnWidth = {'1x'};
gl.RowSpacing  = 8;
gl.Padding     = [10 10 10 10];

hdr = uilabel(gl, 'FontWeight', 'bold', 'FontSize', 13, ...
    'Text', sprintf('%s   |   CSR = %.3f   |   sigma''_v0 = %.1f kPa   |   %d complete cycles', ...
                    char(testID), sel.CSR, sv0, nC));
hdr.Layout.Row = 1;

axg = uigridlayout(gl, [2 2]);
axg.Layout.Row    = 2;
axg.RowSpacing    = 10;
axg.ColumnSpacing = 12;
axg.Padding       = [0 0 0 0];

ax1 = uiaxes(axg); ax1.Layout.Row = 1; ax1.Layout.Column = 1;
ax2 = uiaxes(axg); ax2.Layout.Row = 1; ax2.Layout.Column = 2;
ax3 = uiaxes(axg); ax3.Layout.Row = 2; ax3.Layout.Column = 1;
ax4 = uiaxes(axg); ax4.Layout.Row = 2; ax4.Layout.Column = 2;

ctrl = uigridlayout(gl, [2 4]);
ctrl.Layout.Row  = 3;
ctrl.RowHeight   = {'1x','1x'};
ctrl.ColumnWidth = {150, '1x', 115, 400};
ctrl.RowSpacing  = 4;
ctrl.Padding     = [4 2 4 2];

lc = uilabel(ctrl, 'Text', 'Cycle (coarse):', 'FontWeight', 'bold');
lc.Layout.Row = 1; lc.Layout.Column = 1;

coarseSl = uislider(ctrl, 'Limits', [1 max(2, nC)], 'Value', c0, ...
    'MajorTicks', coarseTicks(nC), 'MinorTicks', coarseMinorTicks(nC));
coarseSl.Layout.Row = 1; coarseSl.Layout.Column = 2;
% Nested-function handles, not anonymous functions: an anonymous function
% captures its variables when it is CREATED, and fineSl does not exist yet.
coarseSl.ValueChangingFcn = @onCoarseChanging;
coarseSl.ValueChangedFcn  = @onCoarseChanged;
if nC < 2
    coarseSl.Enable = 'off';   % a single complete cycle: fine slider only
end

% Numeric cycle box. Typing or stepping here drives the same refresh path
% as the slider; refresh() writes back into it, and a programmatic set of
% Value does not fire ValueChangedFcn, so the two cannot loop.
cycBox = uispinner(ctrl, 'Limits', [1 max(2, nC)], 'Value', c0, ...
                   'Step', 1, 'ValueDisplayFormat', '%.0f');
cycBox.Layout.Row = 1; cycBox.Layout.Column = 3;
cycBox.ValueChangedFcn = @onCycleBox;
if nC < 2
    cycBox.Enable = 'off';
end

lf = uilabel(ctrl, 'Text', 'Fraction (fine):', 'FontWeight', 'bold');
lf.Layout.Row = 2; lf.Layout.Column = 1;

fineSl = uislider(ctrl, 'Limits', [0 1], 'Value', f0, ...
    'MajorTicks', 0:0.25:1, 'MinorTicks', 0:0.05:1);
fineSl.Layout.Row = 2; fineSl.Layout.Column = 2;
fineSl.ValueChangingFcn = @onFineChanging;
fineSl.ValueChangedFcn  = @onFineChanged;

lfv = uilabel(ctrl, 'Text', '', 'HorizontalAlignment', 'left');
lfv.Layout.Row = 2; lfv.Layout.Column = 3;

readout = uilabel(ctrl, 'Text', {''}, 'VerticalAlignment', 'top', ...
                  'FontSize', 11, 'BackgroundColor', [0.96 0.96 0.96]);
readout.Layout.Row = [1 2]; readout.Layout.Column = 4;

bot = uigridlayout(gl, [1 3]);
bot.Layout.Row  = 4;
bot.ColumnWidth = {'1x', 110, 130};
bot.Padding     = [0 0 0 0];

hint = uilabel(bot, 'FontColor', [0.35 0.35 0.35], ...
    'Text', ['Drag the sliders to place N_L, then press Done. ' ...
             'Closing the window or pressing Cancel skips this file.']);
hint.Layout.Row = 1; hint.Layout.Column = 1;

bCancel = uibutton(bot, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) onCancel());
bCancel.Layout.Row = 1; bCancel.Layout.Column = 2;

bDone = uibutton(bot, 'Text', 'Done', 'FontWeight', 'bold', ...
    'BackgroundColor', [0.20 0.55 0.30], 'FontColor', 'w', ...
    'ButtonPushedFcn', @(~,~) onDone());
bDone.Layout.Row = 1; bDone.Layout.Column = 3;

% ========================= STATIC BACKGROUND ==============================
% Drawn ONCE. Slider callbacks only touch the overlay/guide/marker handles.
GREY  = [0.78 0.78 0.78];
COL1  = '#0072BD';   % Ru overlay
COL2  = '#008080';   % stress path overlay
COL3  = '#7E2F8E';   % strain overlay
COL4  = '#1F5C8B';   % loop overlay - deliberately NOT red, so the red
                     % marker and guide stay unambiguous on this panel

% ---- panel 1: measured Ru ----
hold(ax1, 'on'); grid(ax1, 'on');
plot(ax1, FCN, Ru, '-', 'Color', GREY, 'LineWidth', 0.75);
yl1 = [0 1.05];
Ru_refs   = config.expert.RuRefLines;
Ru_colors = {'#2ECC71', '#F39C12', '#E74C3C'};
xl1 = zeroLim(FCN, 0.02);          % cycle axis starts at 0
for kk = 1:numel(Ru_refs)
    plot(ax1, xl1, [Ru_refs(kk) Ru_refs(kk)], '-', ...
         'Color', Ru_colors{min(kk,numel(Ru_colors))}, 'LineWidth', 1.2);
end
for ii = 1:numel(CH_Ru)
    plot(ax1, [CH_Ru(ii) CH_Ru(ii)], yl1, '--', 'Color', '#9B59B6', 'LineWidth', 1.0);
end
autoN = [LiqCriteria.SA.N_L, LiqCriteria.DA.N_L, LiqCriteria.Ru.N_L, LiqCriteria.Stiff.N_L];
autoN(~[LiqCriteria.SA.triggered, LiqCriteria.DA.triggered, ...
        LiqCriteria.Ru.triggered, LiqCriteria.Stiff.triggered]) = NaN;   % not reached
autoC = {'#1ABC9C', '#27AE60', '#E74C3C', '#8E44AD'};
for ii = 1:numel(autoN)
    if isfinite(autoN(ii))
        plot(ax1, [autoN(ii) autoN(ii)], yl1, '-.', 'Color', autoC{ii}, 'LineWidth', 1.1);
    end
end
hOv1a = plot(ax1, NaN, NaN, '-',  'Color', COL1,  'LineWidth', 1.4);
hGd1  = plot(ax1, [NaN NaN], yl1, 'r-', 'LineWidth', 2);
hMk1  = plot(ax1, NaN, NaN, 'ro', 'MarkerSize', 11, ...
              'MarkerFaceColor', 'none', 'LineWidth', 2);
xlim(ax1, xl1); ylim(ax1, yl1);
xlabel(ax1, 'Number of Load Cycles, N_c', 'FontName', FN);
ylabel(ax1, 'Excess Pore Pressure Ratio, R_u', 'FontName', FN);
title(ax1, 'R_u  (grey = full record, dash-dot = automated criteria)');

% ---- panel 2: stress path ----
hold(ax2, 'on'); grid(ax2, 'on');
plot(ax2, sig, tau, '-', 'Color', GREY, 'LineWidth', 0.75);
xl2 = zeroLim(sig, 0.04);          % effective stress axis starts at 0
yl2 = padLim(tau, 0.08);
plot(ax2, xl2, [0 0], ':k');
hOv2 = plot(ax2, NaN, NaN, '-', 'Color', COL2, 'LineWidth', 1.4);
hGd2 = plot(ax2, [NaN NaN], yl2, 'r-', 'LineWidth', 1.5);
hMk2 = plot(ax2, NaN, NaN, 'ro', 'MarkerSize', 11, ...
            'MarkerFaceColor', 'none', 'LineWidth', 2);
xlim(ax2, xl2); ylim(ax2, yl2);
xlabel(ax2, '\sigma''_v (kPa)', 'FontName', FN);
ylabel(ax2, '\tau (kPa)', 'FontName', FN);
title(ax2, 'Effective Stress Path');

% ---- panel 3: strain with SA and DA bounds ----
% SA is a point-wise limit on |gamma|, so it maps straight onto this axis.
% DA is a PER-CYCLE quantity, gamma_DA = gamma_max - gamma_min within the
% cycle, so it has no exact point-wise equivalent. The +/- DA/2 lines are
% the symmetric-cycle equivalent: a loop centred on zero that reaches
% +DA/2 and -DA/2 has gamma_DA exactly at threshold. A loop that has
% drifted to one side can reach DA without touching these lines; the
% automated DA criterion uses the peak-to-peak range and is unaffected.
hold(ax3, 'on'); grid(ax3, 'on');
plot(ax3, FCN, g_pct, '-', 'Color', GREY, 'LineWidth', 0.75);
yl3 = padLim([g_pct; SA_pct; -SA_pct; DA_pct/2; -DA_pct/2], 0.08);
plot(ax3, xl1, [ SA_pct  SA_pct], '--', 'Color', '#C0392B', 'LineWidth', 1.4);
plot(ax3, xl1, [-SA_pct -SA_pct], '--', 'Color', '#C0392B', 'LineWidth', 1.4);
plot(ax3, xl1, [ DA_pct/2  DA_pct/2], '-.', 'Color', '#27AE60', 'LineWidth', 1.4);
plot(ax3, xl1, [-DA_pct/2 -DA_pct/2], '-.', 'Color', '#27AE60', 'LineWidth', 1.4);
% Vertical line at the cycle where the automated DA criterion actually fired
% (peak-to-peak strain between consecutive strain reversals), in the same
% green as the DA bounds.
% Drawn only when DA genuinely reached its threshold: when it did not,
% LiqCriteria.DA.N_L holds the cycle of maximum gamma_DA, which is not a
% trigger point and would be misleading here.
if LiqCriteria.DA.triggered && isfinite(LiqCriteria.DA.N_L)
    plot(ax3, [LiqCriteria.DA.N_L LiqCriteria.DA.N_L], yl3, '-.', ...
         'Color', '#27AE60', 'LineWidth', 1.6);
end
plot(ax3, xl1, [0 0], ':k');
hOv3 = plot(ax3, NaN, NaN, '-', 'Color', COL3, 'LineWidth', 1.4);
hGd3 = plot(ax3, [NaN NaN], yl3, 'r-', 'LineWidth', 2);
hMk3 = plot(ax3, NaN, NaN, 'ro', 'MarkerSize', 11, ...
            'MarkerFaceColor', 'none', 'LineWidth', 2);
xlim(ax3, xl1); ylim(ax3, yl3);
xlabel(ax3, 'Number of Load Cycles, N_c', 'FontName', FN);
ylabel(ax3, 'Shear Strain, \gamma (%)', 'FontName', FN);
title(ax3, sprintf(['Shear Strain  |  SA \\pm%.2f%% (dashed red)  |  ' ...
                    'DA/2 \\pm%.2f%% (dash-dot green)'], SA_pct, DA_pct/2));

% ---- panel 4: stress-strain loops ----
hold(ax4, 'on'); grid(ax4, 'on');
plot(ax4, g_pct, tau, '-', 'Color', GREY, 'LineWidth', 0.75);
xl4 = padLim(g_pct, 0.04);
plot(ax4, xl4, [0 0], ':k');
plot(ax4, [0 0], yl2, ':k');
hOv4 = plot(ax4, NaN, NaN, '-', 'Color', COL4, 'LineWidth', 1.2);
hGd4 = plot(ax4, [NaN NaN], yl2, 'r-', 'LineWidth', 1.5);
hMk4 = plot(ax4, NaN, NaN, 'ro', 'MarkerSize', 11, ...
            'MarkerFaceColor', 'none', 'LineWidth', 2);
xlim(ax4, xl4); ylim(ax4, yl2);
xlabel(ax4, '\gamma (%)', 'FontName', FN);
ylabel(ax4, '\tau (kPa)', 'FontName', FN);
title(ax4, 'Stress-Strain Loops');

% ========================== STATE AND CALLBACKS ===========================
curN = NaN; curIdx = NaN;

refresh(c0, f0);
fprintf('     >>> Slider selection open for %s - set N_L and press Done.\n', char(testID));

uiwait(fig);
return


% ----------------------------------------------------------------- nested -
    function refresh(cVal, fVal)
    %REFRESH  Recompute the selected point and move ONLY the dynamic handles.
        c = min(nC, max(1, round(cVal)));                 % integer snap
        f = min(1, max(0, round(fVal * 100) / 100));      % 0.01 snap
        N = max(0.001, min((c - 1) + f, nC));

        idx = find(FCN >= N, 1, 'first');
        if isempty(idx), idx = nPts; end

        curN = N; curIdx = idx;

        set(hOv1a, 'XData', FCN(1:idx), 'YData', Ru(1:idx));
        set(hOv2,  'XData', sig(1:idx), 'YData', tau(1:idx));
        set(hOv3,  'XData', FCN(1:idx), 'YData', g_pct(1:idx));
        set(hOv4,  'XData', g_pct(1:idx), 'YData', tau(1:idx));

        set(hGd1, 'XData', [N N]);
        set(hGd3, 'XData', [N N]);
        set(hGd2, 'XData', [sig(idx) sig(idx)]);
        set(hGd4, 'XData', [g_pct(idx) g_pct(idx)]);

        set(hMk1, 'XData', FCN(idx),   'YData', Ru(idx));
        set(hMk2, 'XData', sig(idx),   'YData', tau(idx));
        set(hMk3, 'XData', FCN(idx),   'YData', g_pct(idx));
        set(hMk4, 'XData', g_pct(idx), 'YData', tau(idx));

        cycBox.Value = c;                 % programmatic: fires no callback
        lfv.Text     = sprintf('%.2f', f);

        W  = W_run(idx);
        readout.Text = { ...
            sprintf('N_L = %.3f   (cycle %d + %.2f)', N, c, f); ...
            sprintf('sample %d of %d        t = %.3f s', idx, nPts, tsec(idx)); ...
            sprintf('R_u = %.3f', Ru(idx)); ...
            sprintf('gamma = %+.4f %%      tau = %+.3f kPa', g_pct(idx), tau(idx)); ...
            sprintf('gamma_DA of cycle %d = %.4f %%   (threshold %.2f %%)', ...
                    c, gDA(c)*100, DA_pct); ...
            sprintf('sigma''_v = %.2f kPa   sigma''_v/sigma''_v0 = %.3f', ...
                    sig(idx), sig(idx)/sv0); ...
            sprintf('W = %.2f J/m^3   (int tau d-gamma, cumtrapz)', W); ...
            sprintf('W_n = W / sigma''_v0 = %.6f', W / sv0Pa) };

        drawnow limitrate
    end

    function onCoarseChanging(~, ev)
    %ONCOARSECHANGING  Live update while the coarse slider is dragged.
        refresh(ev.Value, fineSl.Value);
    end

    function onCoarseChanged(src, ~)
    %ONCOARSECHANGED  Snap the knob to the integer cycle on release.
        src.Value = min(nC, max(1, round(src.Value)));
        refresh(src.Value, fineSl.Value);
    end

    function onCycleBox(src, ~)
    %ONCYCLEBOX  Typed or stepped cycle number; keeps the slider in step.
        c = min(nC, max(1, round(src.Value)));
        src.Value        = c;
        coarseSl.Value   = c;
        refresh(c, fineSl.Value);
    end

    function onFineChanging(~, ev)
    %ONFINECHANGING  Live update while the fine slider is dragged.
        refresh(coarseSl.Value, ev.Value);
    end

    function onFineChanged(src, ~)
    %ONFINECHANGED  Snap the knob to the nearest 0.01 on release.
        src.Value = min(1, max(0, round(src.Value * 100) / 100));
        refresh(coarseSl.Value, src.Value);
    end

    function onDone()
        if ~isfinite(curN), return; end
        msg = { sprintf('Set the liquefaction point to N_L = %.3f cycles?', curN); ...
                sprintf('R_u = %.3f,   W = %.2f J/m^3', Ru(curIdx), W_run(curIdx)) };
        choice = uiconfirm(fig, msg, 'Confirm liquefaction point', ...
                           'Options', {'Yes','No'}, 'DefaultOption', 1, ...
                           'CancelOption', 2, 'Icon', 'question');
        if strcmp(choice, 'Yes')
            N_L = curN;
            fprintf('     Expert selection: N_L = %.3f cycles (W = %.2f J/m^3)\n', ...
                    curN, W_run(curIdx));
            delete(fig);
        end
        % 'No' falls through and the sliders stay live.
    end

    function onCancel()
        N_L = NaN;
        fprintf('     Expert selection cancelled.\n');
        if isvalid(fig), delete(fig); end
    end

end


function t = coarseTicks(nC)
%COARSETICKS  At most ~10 labelled ticks on the coarse slider.
hi = max(2, nC);
step = max(1, ceil(hi/10));
t = unique([1:step:hi, hi]);
end


function t = coarseMinorTicks(nC)
%COARSEMINORTICKS  Unlabelled ticks between the major ones, so the coarse
%   slider has visible landing marks on long tests. Capped at ~100 marks so
%   the track does not fill in solid, and the major positions are removed so
%   the two sets do not overprint. Returns [] when every integer is already
%   a major tick (short tests), which uislider accepts.
hi = max(2, nC);
step = max(1, ceil(hi/100));
t = setdiff(unique([1:step:hi, hi]), coarseTicks(nC));
end


function [X, bnd, bndOrig] = splitAtZeroShear(X, colF, bandFrac)
%SPLITATZEROSHEAR  Cycle boundaries at the measured shear-force zero crossings.
%   X        channels in columns, one row per sample; column colF is the
%            zeroed shear force (or stress).
%   bandFrac a crossing only counts after the signal has gone beyond
%            -bandFrac*max|F| on the opposite side, so noise around zero
%            cannot create extra cycles.
%   The loading direction s is the sign of the first excursion beyond the
%   band; a cycle ends where s*F rises back through zero. At each crossing
%   a row is inserted, linearly interpolated between the two bracketing
%   samples, with F set exactly to 0 (none is inserted if a sample is
%   already exactly 0). Returns the new X, the boundary row indices bnd
%   (bnd(1) = 1, then one per closed cycle) and bndOrig, the same
%   boundaries as fractional row positions in the ORIGINAL X.
F = X(:, colF);
n = size(X, 1);
bnd = 1; bndOrig = 1;

band = bandFrac * max(abs(F));
iDir = find(abs(F) > band, 1, 'first');
if isempty(iDir) || ~(band > 0), return; end
s = sign(F(iDir));

crossK = zeros(0, 1);                 % crossing between rows k-1 and k
armed  = false;
for k = iDir+1:n
    if s*F(k) < -band, armed = true; end
    if armed && s*F(k-1) < 0 && s*F(k) >= 0
        crossK(end+1, 1) = k; %#ok<AGROW>
        armed = false;
    end
end
nc = numel(crossK);
if nc == 0, return; end

needIns = F(crossK) ~= 0;
Xn      = zeros(n + nnz(needIns), size(X, 2));
bnd     = [1; zeros(nc, 1)];
bndOrig = [1; zeros(nc, 1)];
src = 1; dst = 0;
for j = 1:nc
    k = crossK(j);
    m = k - src;                      % copy rows src .. k-1
    Xn(dst+1:dst+m, :) = X(src:k-1, :);
    dst = dst + m;
    if needIns(j)
        f   = F(k-1) / (F(k-1) - F(k));
        row = X(k-1, :) + f * (X(k, :) - X(k-1, :));
        row(colF) = 0;
        dst = dst + 1;  Xn(dst, :) = row;
        bndOrig(j+1) = (k - 1) + f;
        src = k;
    else                              % sample k is exactly zero
        dst = dst + 1;  Xn(dst, :) = X(k, :);
        bndOrig(j+1) = k;
        src = k + 1;
    end
    bnd(j+1) = dst;
end
m = n - src + 1;
Xn(dst+1:dst+m, :) = X(src:n, :);
X = Xn;
end


function C = grayRedRamp(n)
%GRAYREDRAMP  n colours, light grey -> dark grey -> red, one per cycle
%   (first 80 % grey, then a ramp to red, last 5 % pure red).
C = zeros(n, 3);
gPart = max(1, round(0.80*n));
tPart = max(gPart, round(0.95*n));
for i = 1:n
    if i <= gPart
        r = (i-1) / max(gPart-1, 1);
        g = 0.85 - 0.45*r;
        C(i,:) = [g g g];
    elseif i <= tPart
        r = (i-gPart) / max(tPart-gPart, 1);
        C(i,:) = [0.4 + 0.6*r, 0.4*(1-r), 0.4*(1-r)];
    else
        C(i,:) = [1 0 0];
    end
end
end


function y = smoothThrough(x, v, xq)
%SMOOTHTHROUGH  Smooth curve through every (x, v) point, evaluated at xq.
%   Shape-preserving piecewise cubic (pchip): passes exactly through each
%   point and does not overshoot between them, so R_u stays within the
%   range of neighbouring points (never above 1). xq outside [x(1), x(end)]
%   is clamped to the end values; fewer than two points returns NaN.
x = x(:); v = v(:);
ok = isfinite(x) & isfinite(v);
x = x(ok); v = v(ok);
[x, iu] = unique(x);                % sorted, distinct x for pchip; the
v = v(iu);                          % first of repeated x is kept
if numel(x) < 2, y = nan(size(xq)); return; end
y = pchip(x, v, min(max(xq, x(1)), x(end)));
end


%% =========================================================================
%  CONFIGURATION AND VALIDATION
%  =========================================================================

function config = defaultConfig()

% ----------------------------------------------------------------- batch --
config.batch.startFolder     = pwd;
config.batch.filePattern     = {'*.xlsx', '*.xls'};
config.batch.e0File          = 'specimen_e0.csv';
config.batch.defaultE0       = 0.70;
config.batch.e0Range         = [0.30 1.50];
config.batch.sheetNum        = 1;
config.batch.continueOnError = true;
config.batch.parseFileName   = true;
config.batch.savedE0Wins     = true;
config.batch.testPrefixes    = {'CYC','CYCL','MON','CSS'};

% -------------------------------------------------------------- specimen --
config.specimen.diameter = 70.05;   % mm
config.specimen.height   = 20.00;   % mm (H_0)

% -------------------------------------------------------------- channels --
config.col.time   = 1;
config.col.phase  = 2;
config.col.F_H    = 6;    % horizontal (shear) force,  N
config.col.F_V    = 8;    % vertical force,            N
config.col.disp_H = 9;    % horizontal displacement,   mm
config.col.disp_V = 11;   % vertical displacement,     mm
config.col.cycle  = 13;   % hardware cycle counter (cross-check only)

config.phaseID.consolidation = 1;
config.phaseID.shearing      = 2;
config.import.minRowsShear   = 50;

% ---------------------------------------------------------- segmentation --
config.cycles.zeroBandFrac     = 0.10;   % tau must pass -/+ this x max|tau|
                                        % before the next tau = 0 crossing
                                        % counts (rejects noise near zero)

% -------------------------------------------------------------- criteria --
config.criteria.gamma_SA       = 0.03;
config.criteria.gamma_DA       = 0.05;
config.criteria.Ru             = 0.95;
config.criteria.G_ratio        = 0.10;
config.criteria.primary        = 'EXPERT';
config.criteria.onNotTriggered = 'nan';    % 'nan' | 'lastPoint'

% ---------------------------------------------------------------- expert --
config.expert.mode            = 'interactive';  % stored | interactive | auto | off
                                               % 'interactive' = Always prompt
config.expert.picksFile       = 'expert_picks.csv';
config.expert.changePoints    = true;
config.expert.maxChangePoints = 8;
config.expert.RuRefLines      = [0.90 0.95 0.98];

% ------------------------------------------------------------- QA checks --
config.qa.epsilon_v_warn_pct = 0.5;
config.qa.CSR_refCycles      = 3;

% --------------------------------------------------------- pore pressure --
config.porePressure.envTol = 0.001;  % R_u,max envelope may sit at most this
                                     % far below the measured R_u(t)

% ---------------------------------------------------------------- output --
config.output.excel           = true;
config.output.figures         = true;
config.output.perCycleSheets  = false;  % one sheet per cycle: slow in batch
config.output.subFolder       = 'results';
config.output.masterFile      = 'liq_results_master.xlsx';
config.output.font            = 'Times New Roman';

end


function config = validateConfig(config)

mustBeMemberLocal(config.criteria.primary, {'SA','DA','RU','STIFF','EXPERT'}, ...
                  'criteria.primary');
mustBeMemberLocal(config.criteria.onNotTriggered, {'nan','lastPoint'}, ...
                  'criteria.onNotTriggered');
mustBeMemberLocal(config.expert.mode, {'stored','interactive','auto','off'}, ...
                  'expert.mode');

if strcmpi(config.criteria.primary, 'EXPERT') && strcmpi(config.expert.mode, 'off')
    error('liq:config:expertOff', ...
          'Primary criterion is EXPERT but expert mode is off.');
end
if config.criteria.gamma_DA <= config.criteria.gamma_SA
    error('liq:config:DAvsSA', 'gamma_DA (%.4f) must exceed gamma_SA (%.4f).', ...
          config.criteria.gamma_DA, config.criteria.gamma_SA);
end
if config.specimen.diameter <= 0 || config.specimen.height <= 0
    error('liq:config:geometry', 'Specimen diameter and height must be positive.');
end

f = fieldnames(config.col);
cols = zeros(numel(f),1);
for i = 1:numel(f)
    v = config.col.(f{i});
    if ~isscalar(v) || ~isfinite(v) || v < 1 || mod(v,1) ~= 0
        error('liq:config:col', 'config.col.%s must be a positive integer.', f{i});
    end
    cols(i) = v;
end
if numel(unique(cols)) ~= numel(cols)
    error('liq:config:dupCol', 'Two channels map to the same column.');
end
config.import.minColumns = max(cols);

end


%% =========================================================================
%  IMPORT AND RESULTS CONTAINER
%  =========================================================================

function [RawData, phase1, phase2] = importTestFile(filePath, config)
%IMPORTTESTFILE  Read one export and validate it structurally.

if ~isfile(filePath)
    error('liq:import:missing', 'File not found.');
end

try
    RawData = readmatrix(filePath, 'Sheet', config.batch.sheetNum);
catch ME
    error('liq:import:read', 'Cannot read the file (%s).', ME.message);
end

if isempty(RawData)
    error('liq:import:empty', 'The sheet contains no numeric data.');
end

RawData = RawData(~all(isnan(RawData), 2), :);
if isempty(RawData)
    error('liq:import:empty', 'No usable rows after removing blank lines.');
end

if size(RawData, 2) < config.import.minColumns
    error('liq:import:columns', ...
          'Expected at least %d columns, found %d.', ...
          config.import.minColumns, size(RawData, 2));
end

phaseCol = RawData(:, config.col.phase);
if all(isnan(phaseCol))
    error('liq:import:phase', 'Phase column %d is empty.', config.col.phase);
end

phase1 = RawData(phaseCol == config.phaseID.consolidation, :);
phase2 = RawData(phaseCol == config.phaseID.shearing,      :);

if isempty(phase2)
    error('liq:import:noShear', 'No shearing data (phase %d) found.', ...
          config.phaseID.shearing);
end
if size(phase2,1) < config.import.minRowsShear
    error('liq:import:tooShort', ...
          'Only %d shearing points (minimum %d).', ...
          size(phase2,1), config.import.minRowsShear);
end

needed = {'F_H','F_V','disp_H','disp_V','cycle'};
for i = 1:numel(needed)
    c = config.col.(needed{i});
    if all(isnan(phase2(:, c)))
        error('liq:import:channel', ...
              'Channel "%s" (column %d) is empty during shearing.', needed{i}, c);
    end
end

end


function results = initResultsTable(batch)
%INITRESULTSTABLE  One row per file, pre-filled so a failed file stays blank.

n     = height(batch);
blank = repmat({''}, n, 1);
nanv  = nan(n, 1);

results = table( ...
    batch.File, batch.Sand, batch.Treatment, batch.FC_pct, batch.e0, ...
    batch.sigma_v_kPa, batch.CSR_name, ...
    nanv, nanv, nanv, nanv, nanv, nanv, nanv, ...
    nanv, nanv, nanv, nanv, nanv, nanv, ...
    nanv, nanv, nanv, nanv, nanv, ...
    nanv, nanv, nanv, ...
    blank, blank, blank, blank, ...
    'VariableNames', { ...
      'File','Sand','Treatment','FC_pct','e0','sigma_v_nominal_kPa','CSR_name', ...
      'nPointsConsol','nPointsShear','deltaH_mm','e_ps','sigma_v0_kPa','CSR','nCycles', ...
      'N_L','N_L_SA','N_L_DA','N_L_Ru','N_L_Stiff','N_L_Expert', ...
      'Ru_at_liq','W_at_liq_Jm3','Wn_at_liq','W_pos_Jm3','W_neg_Jm3', ...
      'EnergyRecovery','G_sec1_MPa','tau_res_ratio', ...
      'Criterion','Liquefied','Status','Message'});

% Extra numeric columns appended separately for readability.
results.cumAbsGamma_pct = nanv;
results.epsV_max_pct    = nanv;
results.Ru_max_at_liq   = nanv;   % R_u,max curve (cycle maxima) at N_L
results.Ru_res_at_liq   = nanv;   % R_u,res curve (end of cycle) at N_L
results.W_at_DA_Jm3     = nanv;   % W interpolated at gamma_DA = threshold
results.Wn_at_DA        = nanv;
results.W_at_SA_Jm3     = nanv;   % W at each criterion with its own
results.W_at_Ru_Jm3     = nanv;   % threshold (NaN = never reached)
results.W_at_Stiff_Jm3  = nanv;
results.W_at_Expert_Jm3 = nanv;

results.Status(:) = {'not processed'};

end


function picks = readExpertPicks(picksFile)
%READEXPERTPICKS  Stored expert N_L values keyed by file name.

picks = containers.Map('KeyType', 'char', 'ValueType', 'double');
if ~isfile(picksFile), return; end

try
    T = readtable(picksFile, 'TextType', 'char');
    if all(ismember({'File','N_L'}, T.Properties.VariableNames))
        for i = 1:height(T)
            key = char(string(T.File{i}));
            if ~isempty(key) && isfinite(T.N_L(i))
                picks(key) = T.N_L(i);
            end
        end
    end
catch
    warning('liq:expert:picks', 'Expert picks file unreadable; picks will be re-entered.');
end

end


function writeExpertPicks(picks, picksFile)
%WRITEEXPERTPICKS  Save after every new pick, so a crash loses nothing.

try
    k = keys(picks);
    v = cell2mat(values(picks));
    T = table(k(:), v(:), 'VariableNames', {'File','N_L'});
    writetable(T, picksFile);
catch ME
    warning('liq:expert:save', 'Could not save expert picks: %s', ME.message);
end

end


%% =========================================================================
%  GUI 1 - FILE SELECTION
%  =========================================================================

function batch = selectBatchFiles(config)
%SELECTBATCHFILES  Folder picker plus per-file specimen table.

batch = [];

COL_RUN = 1; COL_FILE = 2; COL_SAND = 3; COL_TRT = 4;
COL_FC  = 5; COL_E0   = 6; COL_SV   = 7; COL_CSR = 8;

fig = uifigure('Name', 'Liquefaction Batch Analysis - Select Files', ...
               'Position', [80 80 1000 660]);
fig.CloseRequestFcn = @(src,~) onCancel(src);

gl = uigridlayout(fig, [4 1]);
gl.RowHeight   = {58, 32, '1x', 38};
gl.ColumnWidth = {'1x'};
gl.RowSpacing  = 8;

top = uigridlayout(gl, [2 3]);
top.Layout.Row  = 1;
top.RowHeight   = {24, 22};
top.ColumnWidth = {90, '1x', 110};
top.Padding     = [0 0 0 0];
top.RowSpacing  = 6;

lblFolder = uilabel(top, 'Text', 'Data folder:', 'FontWeight', 'bold');
lblFolder.Layout.Row = 1; lblFolder.Layout.Column = 1;

folderField = uieditfield(top, 'text', 'Value', '', 'Editable', 'off');
folderField.Layout.Row = 1; folderField.Layout.Column = 2;

btnBrowse = uibutton(top, 'Text', 'Browse...', 'ButtonPushedFcn', @(~,~) onBrowse());
btnBrowse.Layout.Row = 1; btnBrowse.Layout.Column = 3;

statusLbl = uilabel(top, 'Text', 'Select a folder containing the test files.', ...
                    'FontColor', [0.35 0.35 0.35]);
statusLbl.Layout.Row = 2; statusLbl.Layout.Column = [1 3];

tools = uigridlayout(gl, [1 5]);
tools.Layout.Row  = 2;
tools.ColumnWidth = {100, 105, 175, 150, '1x'};
tools.Padding     = [0 0 0 0];

b1 = uibutton(tools, 'Text', 'Select all',   'ButtonPushedFcn', @(~,~) setAll(true));
b1.Layout.Row = 1; b1.Layout.Column = 1;
b2 = uibutton(tools, 'Text', 'Deselect all', 'ButtonPushedFcn', @(~,~) setAll(false));
b2.Layout.Row = 1; b2.Layout.Column = 2;
b3 = uibutton(tools, 'Text', 'Re-read e0 from names', 'ButtonPushedFcn', @(~,~) reparseE0());
b3.Layout.Row = 1; b3.Layout.Column = 3;
b4 = uibutton(tools, 'Text', 'Reload saved e0', 'ButtonPushedFcn', @(~,~) reloadE0());
b4.Layout.Row = 1; b4.Layout.Column = 4;

tbl = uitable(gl, ...
    'ColumnName',       {'Run', 'File name', 'Sand', 'Treatment', 'FC (%)', ...
                         'e0', 'sv (kPa)', 'CSR'}, ...
    'ColumnWidth',      {45, 340, 70, 90, 70, 90, 90, 70}, ...
    'ColumnEditable',   [true false false false false true false false], ...
    'ColumnFormat',     {'logical','char','char','char','numeric','numeric', ...
                         'numeric','numeric'}, ...
    'Data',             cell(0,8), ...
    'CellEditCallback', @(src,evt) onCellEdit(src, evt));
tbl.Layout.Row = 3;

bot = uigridlayout(gl, [1 4]);
bot.Layout.Row  = 4;
bot.ColumnWidth = {'1x', 150, 130, 110};
bot.Padding     = [0 0 0 0];

countLbl = uilabel(bot, 'Text', '', 'FontColor', [0.35 0.35 0.35]);
countLbl.Layout.Row = 1; countLbl.Layout.Column = 1;

bSave = uibutton(bot, 'Text', 'Save e0 to folder', 'ButtonPushedFcn', @(~,~) saveE0(true));
bSave.Layout.Row = 1; bSave.Layout.Column = 2;

btnRun = uibutton(bot, 'Text', 'Run analysis', 'FontWeight', 'bold', ...
                  'BackgroundColor', [0.20 0.55 0.30], 'FontColor', 'w', ...
                  'ButtonPushedFcn', @(~,~) onRun(), 'Enable', 'off');
btnRun.Layout.Row = 1; btnRun.Layout.Column = 3;

bCancel = uibutton(bot, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) onCancel(fig));
bCancel.Layout.Row = 1; bCancel.Layout.Column = 4;

S.folder = '';

onBrowse();
if isvalid(fig), uiwait(fig); end

    function onBrowse()
        startIn = config.batch.startFolder;
        if ~isfolder(startIn), startIn = pwd; end
        f = uigetdir(startIn, 'Select the folder containing the test files');
        if isvalid(fig), drawnow; figure(fig); end
        if isequal(f, 0)
            if isempty(S.folder) && isvalid(fig), onCancel(fig); end
            return
        end
        S.folder = f;
        folderField.Value = f;
        populateTable();
    end

    function populateTable()
        names = {};
        for p = 1:numel(config.batch.filePattern)
            d = dir(fullfile(S.folder, config.batch.filePattern{p}));
            if ~isempty(d)
                d = d(~[d.isdir]);
                if ~isempty(d), names = [names; {d.name}']; end %#ok<AGROW>
            end
        end
        names = unique(names);

        keep = true(numel(names), 1);
        for i = 1:numel(names)
            n = names{i};
            if startsWith(n, '~$') || startsWith(n, '.') || ...
               contains(n, '_CycleData') || contains(n, '_Results') || ...
               contains(n, 'liq_results_master') || ...
               strcmpi(n, config.batch.e0File) || strcmpi(n, config.expert.picksFile)
                keep(i) = false;
            end
        end
        names = names(keep);

        if isempty(names)
            tbl.Data = cell(0,8);
            statusLbl.Text = 'No Excel files found in this folder.';
            statusLbl.FontColor = [0.75 0.20 0.20];
            btnRun.Enable = 'off';
            updateCount();
            return
        end

        savedE0 = readSavedE0();
        data = cell(numel(names), 8);
        nParsed = 0; nSaved = 0; nFailed = 0;

        for i = 1:numel(names)
            info = parseTestName(names{i}, config.batch.testPrefixes);
            data{i,COL_RUN}  = true;
            data{i,COL_FILE} = names{i};
            data{i,COL_SAND} = info.sand;
            data{i,COL_TRT}  = info.treatment;
            data{i,COL_FC}   = info.FC_pct;
            data{i,COL_SV}   = info.sigma_v_kPa;
            data{i,COL_CSR}  = info.CSR;

            if config.batch.savedE0Wins && isKey(savedE0, names{i})
                data{i,COL_E0} = savedE0(names{i});  nSaved = nSaved + 1;
            elseif config.batch.parseFileName && isfinite(info.e0)
                data{i,COL_E0} = info.e0;            nParsed = nParsed + 1;
            elseif isKey(savedE0, names{i})
                data{i,COL_E0} = savedE0(names{i});  nSaved = nSaved + 1;
            else
                data{i,COL_E0} = config.batch.defaultE0; nFailed = nFailed + 1;
            end
        end
        tbl.Data = data;

        msg = sprintf('%d file(s) found - %d e0 from file name, %d from saved values', ...
                      numel(names), nParsed, nSaved);
        if nFailed > 0
            statusLbl.Text = sprintf('%s, %d unparsed (default %.2f - check these).', ...
                                     msg, nFailed, config.batch.defaultE0);
            statusLbl.FontColor = [0.80 0.45 0.10];
        else
            statusLbl.Text = [msg '.'];
            statusLbl.FontColor = [0.35 0.35 0.35];
        end
        btnRun.Enable = 'on';
        updateCount();
    end

    function m = readSavedE0()
        m = containers.Map('KeyType', 'char', 'ValueType', 'double');
        f = fullfile(S.folder, config.batch.e0File);
        if ~isfile(f), return; end
        try
            T = readtable(f, 'TextType', 'char');
            if all(ismember({'File','e0'}, T.Properties.VariableNames))
                for i = 1:height(T)
                    key = char(string(T.File{i}));
                    if ~isempty(key) && isfinite(T.e0(i)), m(key) = T.e0(i); end
                end
            end
        catch
        end
    end

    function saveE0(announce)
        if nargin < 1, announce = false; end
        if isempty(S.folder) || isempty(tbl.Data), return; end
        d = tbl.Data;
        T = table(d(:,COL_FILE), cell2mat(d(:,COL_E0)), 'VariableNames', {'File','e0'});
        try
            writetable(T, fullfile(S.folder, config.batch.e0File));
            if announce
                statusLbl.Text = sprintf('Saved e0 values to %s', config.batch.e0File);
                statusLbl.FontColor = [0.20 0.45 0.25];
            end
        catch ME
            statusLbl.Text = ['Could not save e0 values: ' ME.message];
            statusLbl.FontColor = [0.75 0.20 0.20];
        end
    end

    function reloadE0()
        if isempty(S.folder), return; end
        populateTable();
    end

    function reparseE0()
        d = tbl.Data;
        if isempty(d), return; end
        n = 0;
        for i = 1:size(d,1)
            info = parseTestName(d{i,COL_FILE}, config.batch.testPrefixes);
            if isfinite(info.e0), d{i,COL_E0} = info.e0; n = n + 1; end
        end
        tbl.Data = d;
        statusLbl.Text = sprintf('e0 re-read from %d file name(s).', n);
        statusLbl.FontColor = [0.35 0.35 0.35];
    end

    function setAll(tf)
        d = tbl.Data;
        if isempty(d), return; end
        d(:,COL_RUN) = {tf};
        tbl.Data = d;
        updateCount();
    end

    function onCellEdit(src, evt)
        if evt.Indices(2) == COL_E0
            v  = evt.NewData;
            lo = config.batch.e0Range(1);
            hi = config.batch.e0Range(2);
            if ~isnumeric(v) || ~isscalar(v) || ~isfinite(v) || v < lo || v > hi
                src.Data{evt.Indices(1), COL_E0} = evt.PreviousData;
                statusLbl.Text = sprintf( ...
                    'e0 must be between %.2f and %.2f - entry rejected.', lo, hi);
                statusLbl.FontColor = [0.75 0.20 0.20];
                return
            end
        end
        updateCount();
    end

    function updateCount()
        d = tbl.Data;
        if isempty(d), countLbl.Text = ''; return; end
        countLbl.Text = sprintf('%d of %d file(s) selected', ...
                                sum(cell2mat(d(:,COL_RUN))), size(d,1));
    end

    function onRun()
        d = tbl.Data;
        if isempty(d), return; end
        sel = cell2mat(d(:,COL_RUN));
        if ~any(sel)
            statusLbl.Text = 'No files ticked - nothing to run.';
            statusLbl.FontColor = [0.75 0.20 0.20];
            return
        end
        e0vals = cell2mat(d(:,COL_E0));
        bad = sel & (~isfinite(e0vals) | e0vals < config.batch.e0Range(1) | ...
                     e0vals > config.batch.e0Range(2));
        if any(bad)
            statusLbl.Text = sprintf('Invalid e0 in %d selected row(s).', sum(bad));
            statusLbl.FontColor = [0.75 0.20 0.20];
            return
        end

        saveE0(false);

        batch = table(d(sel,COL_FILE), d(sel,COL_SAND), d(sel,COL_TRT), ...
                      cell2mat(d(sel,COL_FC)), e0vals(sel), ...
                      cell2mat(d(sel,COL_SV)), cell2mat(d(sel,COL_CSR)), ...
                      'VariableNames', {'File','Sand','Treatment','FC_pct','e0', ...
                                        'sigma_v_kPa','CSR_name'});
        batch.Properties.UserData.folder = S.folder;
        delete(fig);
    end

    function onCancel(src)
        batch = [];
        if isvalid(src), delete(src); end
    end

end


function info = parseTestName(fileName, prefixes)
%PARSETESTNAME  Metadata from CYC161-NT-0-0.66-100-0.15c style names.
%   Never errors: an unparsable name simply returns NaN/'' fields.

if nargin < 2 || isempty(prefixes)
    prefixes = {'CYC','CYCL','MON','CSS'};
end

info = struct('testType','', 'sand','', 'treatment','', 'FC_pct',NaN, ...
              'e0',NaN, 'sigma_v_kPa',NaN, 'CSR',NaN, 'repeatID','', 'ok',false);

try
    [~, base] = fileparts(char(fileName));
    parts = strsplit(base, '-');

    if ~isempty(parts{1})
        seg = strtrim(parts{1});
        matched = false;
        [~, ord] = sort(cellfun(@numel, prefixes), 'descend');
        for i = ord(:)'
            p = prefixes{i};
            if strncmpi(seg, p, numel(p)) && numel(seg) > numel(p)
                info.testType = upper(seg(1:numel(p)));
                info.sand     = upper(seg(numel(p)+1:end));
                matched = true;
                break
            end
        end
        if ~matched, info.sand = upper(seg); end
    end

    if numel(parts) >= 2, info.treatment   = upper(strtrim(parts{2})); end
    if numel(parts) >= 3, info.FC_pct      = str2double(regexprep(parts{3}, '[^\d.]', '')); end
    if numel(parts) >= 4, info.e0          = str2double(regexprep(parts{4}, '[^\d.]', '')); end
    if numel(parts) >= 5, info.sigma_v_kPa = str2double(regexprep(parts{5}, '[^\d.]', '')); end

    if numel(parts) >= 6
        tok = regexp(strtrim(parts{6}), '^([\d.]+)\s*([A-Za-z]*)$', 'tokens', 'once');
        if ~isempty(tok)
            info.CSR = str2double(tok{1});
            info.repeatID = tok{2};
        else
            info.CSR = str2double(regexprep(parts{6}, '[^\d.]', ''));
        end
    end
catch
end

info.ok = isfinite(info.e0);

end


%% =========================================================================
%  GUI 2 - RUN OPTIONS
%  =========================================================================

function [config, okRun] = analysisOptionsGUI(config)

okRun = false;

fig = uifigure('Name', 'Liquefaction Batch Analysis - Run Options', ...
               'Position', [140 60 620 790]);
fig.CloseRequestFcn = @(src,~) onCancelOpts(src);

gl = uigridlayout(fig, [6 1]);
gl.RowHeight   = {24, 190, 190, 115, '1x', 38};
gl.ColumnWidth = {'1x'};
gl.RowSpacing  = 12;

hdr = uilabel(gl, 'Text', 'These settings apply to every file in the batch.', ...
              'FontWeight', 'bold');
hdr.Layout.Row = 1;

pCrit = uipanel(gl, 'Title', 'Liquefaction point');
pCrit.Layout.Row = 2;
gCrit = uigridlayout(pCrit, [4 2]);
gCrit.RowHeight   = {28, 28, 28, 28};
gCrit.ColumnWidth = {190, '1x'};
gCrit.RowSpacing  = 8;
gCrit.Padding     = [10 8 10 8];

chkExpert = uicheckbox(gCrit, 'Text', 'Use expert judgment (slider selection on the R_u plot)', ...
                       'Value', ~strcmpi(config.expert.mode, 'off'), ...
                       'ValueChangedFcn', @(~,~) syncEnable());
chkExpert.Layout.Row = 1; chkExpert.Layout.Column = [1 2];

lblPick = uilabel(gCrit, 'Text', 'Expert picks:');
lblPick.Layout.Row = 2; lblPick.Layout.Column = 1;
ddPick = uidropdown(gCrit, ...
    'Items', {'Reuse saved, prompt if missing', 'Always prompt (overwrite saved)', ...
              'Reuse saved, fail if missing'}, ...
    'ItemsData', {'stored','interactive','auto'}, ...
    'Value', pickValue(config.expert.mode));
ddPick.Layout.Row = 2; ddPick.Layout.Column = 2;

lblCrit = uilabel(gCrit, 'Text', 'Primary criterion:');
lblCrit.Layout.Row = 3; lblCrit.Layout.Column = 1;
ddCrit = uidropdown(gCrit, ...
    'Items', {'EXPERT - manual R_u interpretation', ...
              'SA - single-amplitude shear strain', ...
              'DA - double-amplitude shear strain', ...
              'RU - excess pore pressure ratio', ...
              'STIFF - stiffness degradation G/G_1'}, ...
    'ItemsData', {'EXPERT','SA','DA','RU','STIFF'}, ...
    'Value', upper(config.criteria.primary), ...
    'ValueChangedFcn', @(~,~) syncEnable());
ddCrit.Layout.Row = 3; ddCrit.Layout.Column = 2;

lblNT = uilabel(gCrit, 'Text', 'If never triggered:');
lblNT.Layout.Row = 4; lblNT.Layout.Column = 1;
ddNT = uidropdown(gCrit, ...
    'Items', {'Report NaN (did not liquefy)', 'Use last data point'}, ...
    'ItemsData', {'nan','lastPoint'}, 'Value', config.criteria.onNotTriggered);
ddNT.Layout.Row = 4; ddNT.Layout.Column = 2;

pThr = uipanel(gl, 'Title', 'Thresholds');
pThr.Layout.Row = 3;
gThr = uigridlayout(pThr, [4 2]);
gThr.RowHeight   = {28, 28, 28, 28};
gThr.ColumnWidth = {240, 130};
gThr.RowSpacing  = 8;
gThr.Padding     = [10 8 10 8];

l1 = uilabel(gThr, 'Text', 'Single amplitude, gamma_SA (%):');
l1.Layout.Row = 1; l1.Layout.Column = 1;
efSA = uieditfield(gThr, 'numeric', 'Value', config.criteria.gamma_SA*100, ...
                   'Limits', [0 100], 'ValueDisplayFormat', '%.2f');
efSA.Layout.Row = 1; efSA.Layout.Column = 2;

l2 = uilabel(gThr, 'Text', 'Double amplitude, gamma_DA (%):');
l2.Layout.Row = 2; l2.Layout.Column = 1;
efDA = uieditfield(gThr, 'numeric', 'Value', config.criteria.gamma_DA*100, ...
                   'Limits', [0 200], 'ValueDisplayFormat', '%.2f');
efDA.Layout.Row = 2; efDA.Layout.Column = 2;

l3 = uilabel(gThr, 'Text', 'Pore pressure ratio, R_u:');
l3.Layout.Row = 3; l3.Layout.Column = 1;
efRu = uieditfield(gThr, 'numeric', 'Value', config.criteria.Ru, ...
                   'Limits', [0 1], 'ValueDisplayFormat', '%.2f');
efRu.Layout.Row = 3; efRu.Layout.Column = 2;

l4 = uilabel(gThr, 'Text', 'Stiffness ratio, G/G_1:');
l4.Layout.Row = 4; l4.Layout.Column = 1;
efG = uieditfield(gThr, 'numeric', 'Value', config.criteria.G_ratio, ...
                  'Limits', [0 1], 'ValueDisplayFormat', '%.2f');
efG.Layout.Row = 4; efG.Layout.Column = 2;

pOut = uipanel(gl, 'Title', 'Output');
pOut.Layout.Row = 4;
gOut = uigridlayout(pOut, [2 2]);
gOut.RowHeight   = {28, 28};
gOut.ColumnWidth = {190, '1x'};
gOut.RowSpacing  = 8;
gOut.Padding     = [10 8 10 8];

chkExcel = uicheckbox(gOut, 'Text', 'Export results to Excel', ...
                      'Value', config.output.excel);
chkExcel.Layout.Row = 1; chkExcel.Layout.Column = [1 2];

chkFigs = uicheckbox(gOut, 'Text', 'Export figures to PDF', ...
                     'Value', config.output.figures);
chkFigs.Layout.Row = 2; chkFigs.Layout.Column = [1 2];

noteLbl = uilabel(gl, 'Text', '', 'WordWrap', 'on', ...
                  'VerticalAlignment', 'top', 'FontColor', [0.35 0.35 0.35]);
noteLbl.Layout.Row = 5;

bot = uigridlayout(gl, [1 3]);
bot.Layout.Row  = 6;
bot.ColumnWidth = {'1x', 140, 110};
bot.Padding     = [0 0 0 0];

sp = uilabel(bot, 'Text', '');
sp.Layout.Row = 1; sp.Layout.Column = 1;

btnStart = uibutton(bot, 'Text', 'Start analysis', 'FontWeight', 'bold', ...
                    'BackgroundColor', [0.20 0.55 0.30], 'FontColor', 'w', ...
                    'ButtonPushedFcn', @(~,~) onStart());
btnStart.Layout.Row = 1; btnStart.Layout.Column = 2;

btnCancelOpt = uibutton(bot, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) onCancelOpts(fig));
btnCancelOpt.Layout.Row = 1; btnCancelOpt.Layout.Column = 3;

syncEnable();
uiwait(fig);

    function syncEnable()
        useExpert = chkExpert.Value;
        ddPick.Enable    = onOffSwitch(useExpert);
        lblPick.Enable   = onOffSwitch(useExpert);

        if strcmpi(ddCrit.Value, 'EXPERT') && ~useExpert
            noteLbl.Text = ['Primary criterion is EXPERT but expert judgment is ' ...
                            'switched off. Tick the box, or choose another criterion.'];
            noteLbl.FontColor = [0.75 0.20 0.20];
        elseif useExpert && ~strcmpi(ddCrit.Value, 'EXPERT')
            noteLbl.Text = sprintf(['Expert picks are recorded for comparison, but ' ...
                'N_L and the energy at liquefaction come from %s.'], ddCrit.Value);
            noteLbl.FontColor = [0.35 0.35 0.35];
        else
            noteLbl.Text = ['All criteria are computed and reported; the primary one ' ...
                            'defines N_L and therefore W at liquefaction.'];
            noteLbl.FontColor = [0.35 0.35 0.35];
        end
    end

    function onStart()
        if strcmpi(ddCrit.Value, 'EXPERT') && ~chkExpert.Value
            syncEnable(); return
        end
        if efDA.Value <= efSA.Value
            noteLbl.Text = 'gamma_DA must exceed gamma_SA.';
            noteLbl.FontColor = [0.75 0.20 0.20];
            return
        end

        if chkExpert.Value
            config.expert.mode = ddPick.Value;
        else
            config.expert.mode = 'off';
        end
        config.criteria.primary        = ddCrit.Value;
        config.criteria.onNotTriggered = ddNT.Value;
        config.criteria.gamma_SA       = efSA.Value / 100;
        config.criteria.gamma_DA       = efDA.Value / 100;
        config.criteria.Ru             = efRu.Value;
        config.criteria.G_ratio        = efG.Value;
        config.output.excel            = chkExcel.Value;
        config.output.figures          = chkFigs.Value;

        okRun = true;
        delete(fig);
    end

    function onCancelOpts(src)
        okRun = false;
        if isvalid(src), delete(src); end
    end

    function v = pickValue(mode)
        if any(strcmpi(mode, {'stored','interactive','auto'}))
            v = lower(mode);
        else
            v = 'stored';
        end
    end

end


%% =========================================================================
%  SMALL HELPERS
%  =========================================================================

function h = newFigure(name)
%NEWFIGURE  Invisible figure sized for export; nothing appears on screen.
h = figure('Name', name, 'NumberTitle', 'off', 'Visible', 'off', ...
           'Color', 'w', 'Position', [50 50 1500 850]);
end


function logf(fid, fmt, varargin)
fprintf(fmt, varargin{:});
if ~isempty(fid) && fid > 0
    try
        fprintf(fid, fmt, varargin{:}); catch, end %#ok<CTCH>
end
end


function closeLog(fid)
if ~isempty(fid) && fid > 0
    try fclose(fid); catch, end %#ok<CTCH>
end
end


function closeIfValid(h)
if ~isempty(h) && all(isvalid(h)), close(h); end
end


function closeNewFigures(figsBefore)
%CLOSENEWFIGURES  Close only the figures created since figsBefore was taken.
figsNow = findall(groot, 'Type', 'figure');
if isempty(figsNow), return; end
isNew = true(size(figsNow));
for i = 1:numel(figsNow)
    if any(figsNow(i) == figsBefore), isNew(i) = false; end
end
h = figsNow(isNew);
h = h(isvalid(h));
if ~isempty(h), close(h); end
end


function L = padLim(v, frac)
%PADLIM  Finite axis limits with a fractional margin; safe on degenerate data.
%   Used by expertPickGUI so the red guide lines can span a fixed y-range
%   without being recomputed on every slider callback.
v = v(isfinite(v));
if isempty(v), L = [0 1]; return; end
lo = min(v); hi = max(v);
if hi <= lo, lo = lo - 1; hi = hi + 1; end
p = (hi - lo) * frac;
L = [lo - p, hi + p];
end


function L = zeroLim(v, frac)
%ZEROLIM  Axis limits anchored at zero, with a fractional margin at the top.
%   Used where the quantity is non-negative by nature (cycle number,
%   effective vertical stress) and the axis should therefore start at 0.
%   Any negative excursion in v is clipped by design - use padLim for
%   signed quantities such as shear strain or shear stress.
v = v(isfinite(v));
if isempty(v), L = [0 1]; return; end
hi = max(max(v), 0);
if hi <= 0, hi = 1; end
L = [0, hi * (1 + frac)];
end


function s = onOffStr(tf)
if tf, s = 'enabled'; else, s = 'disabled'; end
end


function v = onOffSwitch(tf)
if tf, v = 'on'; else, v = 'off'; end
end


function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end


function v = valOrNaN(v, makeNaN)
if makeNaN, v = NaN; end
end


function s = fmtNum(v, fmt)
if isnan(v), s = 'NaN'; else, s = sprintf(fmt, v); end
end


function s = texSafe(str)
%TEXSAFE  Escape underscores so test IDs render literally in titles.
s = strrep(char(str), '_', '\_');
end


function mustBeMemberLocal(val, allowed, name)
if ~(ischar(val) || isstring(val)) || ~any(strcmpi(char(val), allowed))
    error('liq:config:member', '%s must be one of: %s', name, strjoin(allowed, ', '));
end
end