% Setting up and solving the 2D flow horizontal rectangular system (2Dfhrs)
% In MATLAB, this file produces Figure 7 in [A]. In GNU Octave, this file
% creates and prints the results in the folder vtk_micp_2Dfhrs which can
% be visualized using ParaView.
%
% The example assumes MRST is the Matlab/Octave path. For information on
% MRST-functions, confer the MRST documentation at
%   http://www.sintef.no/projectweb/mrst/
% 
%{
Copyright 2021, NORCE Norwegian Research Centre AS, Computational 
Geosciences and Modeling.

This file is part of the ad-micp module.

ad-micp is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

ad-micp is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this file.  If not, see <http://www.gnu.org/licenses/>.
%}

% To get distmesh for first time, uncomment and run the following lines
% pth = fullfile(ROOTDIR,'utils','3rdparty','distmesh');
% mkdir(pth)
% unzip('http://persson.berkeley.edu/distmesh/distmesh.zip', pth);
% mrstPath('reregister','distmesh', pth);

% Required modules
pth = fullfile(ROOTDIR,'utils','3rdparty','distmesh');
mrstPath('reregister','distmesh', pth);
mrstModule add deckformat ad-core ad-blackoil ad-micp ad-props mrst-gui ...
                                                                   distmesh

% Grid 
L = 75;            % Aquifer length, m
Wh = 10;           % Aquifer width, m
if exist('OCTAVE_VERSION', 'builtin') ~= 0 %GNU Octave
    B = 25;        % hmin to hmax transition radius, m
    hmin = .75;    % Minimum grid size, m
    hmax = 10;     % Maximum grid size, m
    fd=@(p) drectangle(p,-L,L,-Wh,Wh);
    fh = @(p) hmin+.3*abs(dcircle(p,0,0,0)).* (abs(dcircle(p,0,0,0))<B)+...
      min(hmin+.3*abs(dcircle(p,0,0,B)),hmax).* (abs(dcircle(p,0,0,0))>=B);
    [p,t]=distmesh2d(fd, fh, hmin, [-L,-Wh;L,Wh], ...
                                            [-L,-Wh;L,-Wh;-L,Wh;L,Wh;0,0]);
    G = makeLayeredGrid(pebi(triangleGrid(p, t)),1);
    close
else %MATLAB
    [X1,Y1] = meshgrid((-L:5:L), (-Wh:5:Wh));
    [X2,Y2] = meshgrid((-30:.5:-1.5), (-Wh:.5:Wh));
    [X3,Y3] = meshgrid((1.5:.5:30), (-Wh:.5:Wh));
    rr=-1:0.125:0;
    Pw = [];
    for l = 4*exp(rr)
        [x,y,z] = cylinder(l,50); 
        Pw = [Pw [x(1,:); y(1,:)]];
    end
    Pw = [Pw [0; 0]];
    Pw1 = bsxfun(@plus, Pw, [0; 0]);
    P = unique([Pw1'; X1(:) Y1(:); X2(:) Y2(:); X3(:) Y3(:)], 'rows');
    G = triangleGrid(P);
    G = computeGeometry(G);
    G = makeLayeredGrid(pebi(G),1);
end
G = computeGeometry(G);
c = G.cells.centroids;
C = ones(G.cells.num,1);

% Rock
K0 = 1e-12*C;                % Aquifer permeability, m^2
porosity = 0.2;              % Aquifer porosity, [-]
rock = makeRock(G, K0, porosity);

% Fluid properties
fluid.muw = 2.535e-4;        % Water viscocity, Pa s                            
fluid.bW   =  @(p) 0*p + 1;  % Water formation volume factor, [-]
fluid.bO   =  @(p) 0*p + 1;  % CO2 formation volume factor, [-]
fluid.rhoWS = 1045;          % Water density, kg/m^3
fluid.rhoOS = 479;           % CO2 density, kg/m^3

% Remaining model parameters (we put them on the fluid structure)
fluid.rho_b = 35;            % Density (biofilm), kg/m^3
fluid.rho_c = 2710;          % Density (calcite), kg/m^3
fluid.k_str = 2.6e-10;       % Detachment rate, m/(Pa s)
fluid.diffm = 2.1e-9;        % Diffusion coefficient (microbes), m^2/s
fluid.diffo = 2.32e-9;       % Diffusion coefficient (oxygen), m^2/s
fluid.diffu = 1.38e-9;       % Diffusion coefficient (urea), m^2/s
fluid.alphaL = 1e-3;         % Disperison coefficient (longitudinal), m
fluid.alphaT = 4e-4;         % Disperison coefficient (transverse), m
fluid.eta = 3;               % Fitting factor, [-]
fluid.k_o = 2e-5;            % Half-velocity constant (oxygen), kg/m^3
fluid.k_u = 21.3;            % Half-velocity constant (urea), kg/m^3
fluid.mu = 4.17e-5;          % Maximum specific growth rate, 1/s
fluid.mu_u = 0.0161;         % Maximum rate of urease utilization, 1/s
fluid.k_a = 8.51e-7;         % Microbial attachment rate, 1/s                                         
fluid.k_d = 3.18e-7;         % Microbial death rate, 1/s
fluid.Y = 0.5;               % Yield growth coefficient, [-]
fluid.Yuc = 1.67;            % Yield coeccifient (calcite/urea), [-]
fluid.F = 0.5;               % Oxygen consumption factor, [-]
fluid.crit = .1;             % Critical porosity, [-]
fluid.kmin = 1e-20;          % Minimum permeability, m^2
fluid.cells = C;             % Array with all cells, [-]
fluid.ptol = 1e-4;           % Porosity tolerance to stop the simulation 

% Porosity-permeability relationship
fluid.K = @(poro) (K0.*((poro-fluid.crit)/(porosity-fluid.crit))...
        .^fluid.eta+fluid.kmin).*K0./(K0+fluid.kmin).*(poro>fluid.crit)+...
                                            fluid.kmin.*(poro<=fluid.crit);

% Maximum values (to ease the convergence of the solution)
fluid.omax = .04;                 % Maximum injected oxygen concentration 
fluid.umax = 300;                 % Maximum injected urea concentration
fluid.mmax = 105;                 % Maximum value of biomass concentration
fluid.bmax = porosity-fluid.ptol; % Maximum biofilm volume fraction
fluid.cmax = porosity-fluid.ptol; % Maximum calcite volume fraction

% Create Well
Q = 7.2e-4;   % Injection rate m^3/s
Cm = 0.01;    % Injected microbial concentration kg/m^3
r = 0.15;     % Well radius, m
[~,iw]= min(abs(c(:,1).^2+c(:,2).^2));
W = addWell([], G, rock, iw, 'Type', 'rate', 'Comp_i', [1,0],'Val', Q, ...
                                                              'Radius', r);
W.o = 0;
W.u = 0;
W.m = Cm;
G.injectionwellonboundary = 0; 

% Create model
model = MICPModel(G, rock, fluid);

% Boundary condition
f = boundaryFaces(G);
f = f(abs(G.faces.normals(f,1))>eps & abs(G.faces.centroids(f,1))>L-.01);
bc = addBC([], f, 'pressure', atm, 'sat', [0 0]);
bc.o = zeros(size(bc.sat,1), 1);
bc.u = zeros(size(bc.sat,1), 1);
bc.m = zeros(size(bc.sat,1), 1);
bc.b = zeros(size(bc.sat,1), 1);
bc.c = zeros(size(bc.sat,1), 1);

% Setup some schedule
dt = hour;
nt = 1000*hour/dt;
clear schedule
timesteps = repmat(dt, nt, 1);

% Well different rates and times
N = 17; % Number of injection changes
M = zeros(N,5); % Matrix where entries per row are:time, rate, o, u, m.
M(1,1) = 20*hour/dt; 
M(1,2) = Q;
M(2,1) = 40*hour/dt; 
M(2,2) = eps; 
M(3,1) = 140*hour/dt; 
M(3,2) = Q;
M(3,3) = fluid.omax;
M(4,1) = 160*hour/dt;
M(4,2) = Q;
M(5,1) = 180*hour/dt; 
M(5,2) = eps; 
M(6,1) = 230*hour/dt; 
M(6,2) = Q;
M(6,4) = fluid.umax;
M(7,1) = 250*hour/dt; 
M(7,2) = Q;
M(8,1) = 270*hour/dt; 
M(8,2) = eps;
M(9,1) = 500*hour/dt; 
M(9,2) = Q;
M(9,5) = Cm;
M(10,1) = 520*hour/dt; 
M(10,2) = Q;
M(11,1) = 540*hour/dt; 
M(11,2) = eps; 
M(12,1) = 640*hour/dt; 
M(12,2) = Q;
M(12,3) = fluid.omax;
M(13,1) = 660*hour/dt;
M(13,2) = Q;
M(14,1) = 680*hour/dt; 
M(14,2) = eps; 
M(15,1) = 730*hour/dt; 
M(15,2) = Q;
M(15,4) = fluid.umax;
M(16,1) = 750*hour/dt; 
M(16,2) = Q;
M(17,1) = 770*hour/dt; 
M(17,2) = eps;

% Make schedule
schedule = simpleSchedule(timesteps,'W',W,'bc',bc);
for i=1:N
    schedule.control(i+1) = schedule.control(i);
    schedule.control(i+1).W.val = M(i,2);
    schedule.control(i+1).W.o = M(i,3);
    schedule.control(i+1).W.u = M(i,4);
    schedule.control(i+1).W.m = M(i,5);
    schedule.step.control(M(i,1):end) = i+1;
end    

% Initial condition
state0      = initState(G, W, atm, [1, 0]);
state0.o    = zeros(G.cells.num,1);
state0.u    = zeros(G.cells.num,1);
state0.m    = zeros(G.cells.num,1);
state0.b    = zeros(G.cells.num,1);
state0.c    = zeros(G.cells.num,1);

% Simulate case (GNU Octave/MATLAB)
if exist('OCTAVE_VERSION', 'builtin') ~= 0
    ok = 'true';
    fn = checkCloggingMICP(ok);
else
    fn = getPlotAfterStepMICP(state0, model, 0, 90);
end
[~, states] = simulateScheduleAD(state0, model, schedule,'afterStepFn',fn);

% Write the results to be read in ParaView (GNU Octave)
if exist('OCTAVE_VERSION', 'builtin') ~= 0
    mkdir vtk_micp_2Dfhrs;
    cd vtk_micp_2Dfhrs;
    mrsttovtk(G,states,'states','%f');
    return
end

% Figure 7 paper (MATLAB)
figure;
ccc=flipud(jet);
ccc=ccc(70:1:end,:);
set(gcf,'PaperUnits','inches','PaperSize',[6.83 1.85],'PaperPosition', ...
                                                          [0 0 6.83 1.85]);
set(gca,'FontName','Arial');
n1=subplot(1,2,1);
colormap (n1,ccc);
caxis([0 100]);
axis equal tight
colorbar()
cb = colorbar; 
title(cb, '$\%$','FontSize',8,'Interpreter','latex','FontName','Arial');
set(cb,'location','northoutside','YTick',[0 25 50 75 100]);
xlabel({'x [m]'; '(a)'},'FontSize',8,'FontName','Arial');
ylabel('y [m]','FontSize',8,'FontName','Arial');
s=plotCellData(G,100*(1-fluid.K(porosity-states{nt/2}.c-states{nt/2}.b)...
                                                                    ./K0));
s.EdgeColor = 'none';
title('Permeability reduction (after phase I)','FontSize',8, ...
                                 'FontName','Arial','Interpreter','latex');
set(gca,'FontSize',8,'XTick',-L:25:L,'YTick',(-Wh:10:Wh),'color', ...
                                                'none','FontName','Arial');
ylim([-Wh,Wh]);
rectangle('Position',[10,-Wh,5,2*Wh],'LineWidth',2,'LineStyle','-', ...
                                                   'edgecolor','[0 0 0]');
n2=subplot(1,2,2);
axis equal tight
colormap (n2,ccc);
caxis([0 100]);
cb = colorbar; 
title(cb, '$\%$','FontSize',8,'Interpreter','latex','FontName','Arial');
set(cb,'location','northoutside','YTick',[0 25 50 75 100]);
xlabel({'x [m]'; '(b)'},'FontSize',8,'FontName','Arial');
ylabel('y [m]','FontSize',8,'FontName','Arial');
s=plotCellData(G,100*(1-fluid.K(porosity-states{nt}.c-states{nt}.b)./K0));
s.EdgeColor = 'none';
title('Permeability reduction (after phase II)','FontSize',8, ...
                                 'FontName','Arial','Interpreter','latex');
set(gca,'FontSize',8,'XTick',-L:25:L,'YTick',(-Wh:10:Wh),'color', ...
                                                'none','FontName','Arial');
ylim([-Wh,Wh]);
rectangle('Position',[10,-Wh,5,2*Wh],'LineWidth',2,'LineStyle','-', ...
                                                   'edgecolor','[0 0 0]');
%print -depsc2 Fig7.eps