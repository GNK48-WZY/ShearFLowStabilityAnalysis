
Re_list = logspace(log10(200), log10(2000), 16);
delta_list = logspace(-6, 0, 200);  
Lx = 1.75*pi;
Lz = 1.2*pi;
alpha = (2*pi)/Lx;
Beta = pi/2;
Gamma = 2*pi/Lz;
KBG = sqrt(Beta^2+Gamma^2);
KAG = sqrt(alpha^2+Gamma^2);
KABG = sqrt(alpha^2+Beta^2+Gamma^2);
deltaf = zeros(length(Re_list), length(delta_list));
delta_max = zeros(1, length(Re_list));
delta_opt = zeros(length(Re_list), length(delta_list));
delete(gcp('nocreate'));
parpool(8);

parfor ind_Re = 1:length(Re_list)
    Re = Re_list(ind_Re);
    [local_deltaf, local_delta_opt, local_u_upper_bound, local_Gamma_theorem] = SOS_Re(Re, Gamma, Beta, alpha, delta_list, KBG, KAG, KABG);
    delta_opt(ind_Re, :) = local_delta_opt;
    deltaf(ind_Re, :) = local_deltaf;
    delta_max(ind_Re) = max(local_deltaf);
    u_upper_bound_SOS(ind_Re, :) = local_u_upper_bound;
    [u_upper_bound_max_SOS(ind_Re), ind_u_upper_bound_max_SOS(ind_Re)]= max(local_u_upper_bound);
    [Gamma_theorem_max_SOS(ind_Re), ind_Gamma_theorem_max_SOS(ind_Re)]= max(local_Gamma_theorem);
    [Gamma_theorem_min_SOS(ind_Re), ind_Gamma_theorem_min_SOS(ind_Re)]= min(local_Gamma_theorem);
    Gamma_theorem_SOS(ind_Re, :) = local_Gamma_theorem;
end


log_Re_list = log10(Re_list);
log_delta_max = log10(delta_max);

% line fitting to the data
coeffs = polyfit(log_Re_list, log_delta_max, 1);
sigma = coeffs(1);
A_log = coeffs(2);
figure;
loglog(Re_list, delta_max, 'o'); hold on;
fit_line = 10.^polyval(coeffs, log_Re_list);
loglog(Re_list, fit_line, '-');
xlabel('Re');
ylabel('\delta_{p}');
title(['Scaling exponent \sigma = ', num2str(sigma)]);

disp(['Scaling exponent (sigma): ', num2str(sigma)]);
disp(['Intercept (A): ', num2str(A_log)]);


function [local_deltaf, local_delta_opt, local_u_upper_bound, local_Gamma_theorem] = SOS_Re(Re,Gamma, Beta, alpha,delta_list, KBG, KAG, KABG)
   local_delta_opt = NaN*ones(1, length(delta_list));
   local_deltaf = NaN*ones(1, length(delta_list));
   local_u_upper_bound = NaN*ones(1,length(delta_list));
   local_Gamma_theorem = NaN*ones(1,length(delta_list));
   linear = [(Beta^2)/Re;
    ((4*Beta^2)/3 + Gamma^2)/Re;
    (Beta^2+Gamma^2)/Re;
    (3*alpha^2+4*Beta^2)/(3*Re);
    (alpha^2+Beta^2)/Re;
    (3*alpha^2+4*Beta^2+3*Gamma^2)/(3*Re);
    (alpha^2+Beta^2+Gamma^2)/Re;
    (alpha^2+Beta^2+Gamma^2)/Re;
    (9*Beta^2)/Re];
   

   for ind_delta = 1:length(delta_list)
        delta = delta_list(ind_delta);
        %P = sdpvar(9,9);
        %R = sdpvar(9,9);
        a = sym('a', [9, 1]);
        epsilon = 0.01;
        %a=sdpvar(9,1);
        % a' * P * a;
        nonlinear = nonliner(a, Gamma, Beta, alpha, KBG, KABG, KAG);  
        
        nonlinear_gradient = sym(zeros(length(a), length(a)));
        for i = 1:length(nonlinear)
             nonlinear_gradient(i, :) = gradient(nonlinear(i), a);
        end
        a_bar = [1;0;0;0;0;0;0;0;0];
        nonlinear_gradient_sub = double(subs(nonlinear_gradient, a, a_bar));
        RHS_J_mean_shear = nonlinear_gradient_sub;
        RHS_R_viscous = diag(double(linear));
        A = RHS_J_mean_shear- RHS_R_viscous;

        % Conversion of YALMIP code to SOSTOOLS format
        pvar x1 x2 x3 x4 x5 x6 x7 x8 x9; % Declare variables
        x = [x1; x2; x3; x4; x5; x6; x7; x8; x9]; % Variables vector
        nonlinear_sdp = nonliner2(x, Gamma, Beta, alpha, KBG, KABG, KAG); 
        % Initialize SOS program
        prog = sosprogram(x);
        % Define V(x) as a polynomial of degree 2
        Z_V = monomials(x, 2); % Monomials up to degree 2 for V(x)
        [prog, V_poly] = sospolyvar(prog, Z_V); % V(x) with symbolic coefficients
        % Define R(x) as a polynomial of degree 2
        Z_R = monomials(x, 0:2); % Monomials up to degree 2 for R(x)
        [prog, R_poly] = sospolyvar(prog, Z_R); % R(x) with symbolic coefficients
        % Derivative of lyapunov function 
        V_dot = jacobian(V_poly, x) * (nonlinear_sdp + A * x);
        % Define the SOS constraints
        SOS_constraint = V_dot + (delta^2 - transpose(x) * x) * transpose(x) * (R_poly) * x + epsilon * transpose(x) * x;
        % Add SOS constraints
        prog = sosineq(prog, -SOS_constraint); % SOS_constraint must be SOS
        prog = sosineq(prog, V_poly - epsilon * transpose(x) * x); % V(x) - ��*x'*x must be SOS
        prog = sosineq(prog, R_poly); % R(x) must be SOS
        
        solver_opt.solver = 'sedumi';
        [prog,info] = sossolve(prog, solver_opt);
        
        V_sol = sosgetsol(prog, V_poly); % Retrieve V(x) solution
        R_sol = sosgetsol(prog, R_poly); % Retrieve R(x) solution

        

        % if sol.problem == 0
        if prog.solinfo.info.pinf==0 && prog.solinfo.info.dinf==0
            
            %For pvar data structures, hessian cannot work and it needs to
            %use the brute force to compute P matrix
            for i=1:9
                for j=1:9
                    P(i,j)=diff(diff(V_sol,x(i)),x(j))/2; 
                end
            end
            P=double(P); %convert to double data structure. 
            umax = max(eig(P)); % c2
            umin = min(eig(P)); % c1
            % P=P/2;
            %P = value(hessian(V_poly, x));
            %R = value(hessian(R_poly, x));
            local_delta_opt(ind_delta) = delta;
            local_deltaf(ind_delta)=double(local_delta_opt(ind_delta)*sqrt(min(eig(P))/max(eig(P))));
            c3 = epsilon;
            c2 = umax;
            c1 = umin;
            L = norm(B);
            c4 = norm(2*P);
            eta_1 = norm(C);
            eta_2 = 0;  
            local_Gamma_theorem(ind_delta) = eta_2 + (eta_1*c2*c4*L)/(c1*c3);        
            local_u_upper_bound(ind_delta) = (c1*c3*delta)/(c2*c4*L);
            disp('SOS successful!');
            disp(['Feasible solution found for Re = ', num2str(Re), ', delta = ', num2str(delta_list(ind_delta))]);
        else
            disp('Problem infeasible');
            disp(['No feasible solution found for Re = ', num2str(Re), ', delta = ', num2str(delta_list(ind_delta))]);
        end
   end
end


function nonlinear = nonliner(a, Gamma, Beta, alpha, KBG, KABG, KAG)
        term1 = -sqrt(3/2)*Beta*Gamma*a(6)*a(8)/KABG + sqrt(3/2)*Beta*Gamma*a(2)*a(3)/KBG;
        term2 = (5/3)*sqrt(2/3)*Gamma^2*a(4)*a(6)/KAG - Gamma^2*a(5)*a(7)/(sqrt(6)*KAG) ...
                 - alpha*Beta*Gamma*a(5)*a(8)/(sqrt(6)*KAG*KABG) - sqrt(3/2)*Beta*Gamma*a(1)*a(3)/KBG - sqrt(3/2)*Beta*Gamma*a(3)*a(9)/KBG;
        term3 = 2*alpha*Beta*Gamma*(a(4)*a(7) + a(5)*a(6))/(sqrt(6)*KAG*KBG) + (Beta^2*(3*alpha^2+Gamma^2) - 3*Gamma^2*(alpha^2+Gamma^2))*a(4)*a(8)/(sqrt(6)*KAG*KBG*KABG);
        term4 = -alpha*a(1)*a(5)/sqrt(6) - 10*alpha^2*a(2)*a(6)/(3*sqrt(6)*KAG) ...
                   - sqrt(3/2)*alpha*Beta*Gamma*a(3)*a(7)/KAG*KBG - sqrt(3/2)*alpha^2*Beta^2*a(3)*a(8)/KAG*KBG*KABG - alpha*a(5)*a(9)/sqrt(6);
        term5 = alpha*a(1)*a(4)/sqrt(6) + alpha^2*a(2)*a(7)/(sqrt(6)*KAG) - alpha*Beta*Gamma*a(2)*a(8)/(sqrt(6)*KAG*KABG) + alpha*a(4)*a(9)/sqrt(6) + 2*alpha*Beta*Gamma*a(3)*a(6)/(sqrt(6)*KAG*KBG);
        term6 = alpha*a(1)*a(7)/sqrt(6) + sqrt(3/2)*Beta*Gamma*a(1)*a(8)/KABG ...
                 + 10*(alpha^2-Gamma^2)*a(2)*a(4)/(KAG*3*sqrt(6)) - 2*sqrt(2/3)*a(3)*a(5)*alpha*Beta*Gamma/(KAG*KBG) + alpha*a(7)*a(9)/sqrt(6) + sqrt(3/2)*Beta*Gamma*a(8)*a(9)/KABG;
        term7 = -alpha*(a(1)*a(6) + a(6)*a(9))/sqrt(6) + (Gamma^2-alpha^2)*a(2)*a(5)/(sqrt(6)*KAG) + alpha*Beta*Gamma*a(3)*a(4)/(sqrt(6)*KAG*KBG);
        term8 = 2*alpha*Beta*Gamma*a(2)*a(5)/(sqrt(6)*KAG*KABG) + Gamma^2*(3*alpha^2-Beta^2+3*Gamma^2)*a(3)*a(4)/(sqrt(6)*KAG*KBG*KABG);
        term9 = sqrt(3/2)*Beta*Gamma*a(2)*a(3)/KBG - sqrt(3/2)*Beta*Gamma*a(6)*a(8)/KABG;

        nonlinear= [term1;
                    term2;
                    term3;
                    term4;
                    term5;
                    term6;
                    term7;
                    term8;
                    term9];
end
                
function nonlinear_sdp = nonliner2(x, Gamma, Beta, alpha, KBG, KABG, KAG)    
        term1 = -sqrt(3/2)*Beta*Gamma*x(6)*x(8)/KABG + sqrt(3/2)*Beta*Gamma*x(2)*x(3)/KBG;
        term2 = (5/3)*sqrt(2/3)*Gamma^2*x(4)*x(6)/KAG - Gamma^2*x(5)*x(7)/(sqrt(6)*KAG) ...
                 - alpha*Beta*Gamma*x(5)*x(8)/(sqrt(6)*KAG*KABG) - sqrt(3/2)*Beta*Gamma*x(1)*x(3)/KBG - sqrt(3/2)*Beta*Gamma*x(3)*x(9)/KBG;
        term3 = 2*alpha*Beta*Gamma*(x(4)*x(7) + x(5)*x(6))/(sqrt(6)*KAG*KBG) + (Beta^2*(3*alpha^2+Gamma^2) - 3*Gamma^2*(alpha^2+Gamma^2))*x(4)*x(8)/(sqrt(6)*KAG*KBG*KABG);
        term4 = -alpha*x(1)*x(5)/sqrt(6) - 10*alpha^2*x(2)*x(6)/(3*sqrt(6)*KAG) ...
                   - sqrt(3/2)*alpha*Beta*Gamma*x(3)*x(7)/KAG*KBG - sqrt(3/2)*alpha^2*Beta^2*x(3)*x(8)/KAG*KBG*KABG - alpha*x(5)*x(9)/sqrt(6);
        term5 = alpha*x(1)*x(4)/sqrt(6) + alpha^2*x(2)*x(7)/(sqrt(6)*KAG) - alpha*Beta*Gamma*x(2)*x(8)/(sqrt(6)*KAG*KABG) + alpha*x(4)*x(9)/sqrt(6) + 2*alpha*Beta*Gamma*x(3)*x(6)/(sqrt(6)*KAG*KBG);
        term6 = alpha*x(1)*x(7)/sqrt(6) + sqrt(3/2)*Beta*Gamma*x(1)*x(8)/KABG ...
                 + 10*(alpha^2-Gamma^2)*x(2)*x(4)/(KAG*3*sqrt(6)) - 2*sqrt(2/3)*x(3)*x(5)*alpha*Beta*Gamma/(KAG*KBG) + alpha*x(7)*x(9)/sqrt(6) + sqrt(3/2)*Beta*Gamma*x(8)*x(9)/KABG;
        term7 = -alpha*(x(1)*x(6) + x(6)*x(9))/sqrt(6) + (Gamma^2-alpha^2)*x(2)*x(5)/(sqrt(6)*KAG) + alpha*Beta*Gamma*x(3)*x(4)/(sqrt(6)*KAG*KBG);
        term8 = 2*alpha*Beta*Gamma*x(2)*x(5)/(sqrt(6)*KAG*KABG) + Gamma^2*(3*alpha^2-Beta^2+3*Gamma^2)*x(3)*x(4)/(sqrt(6)*KAG*KBG*KABG);
        term9 = sqrt(3/2)*Beta*Gamma*x(2)*x(3)/KBG - sqrt(3/2)*Beta*Gamma*x(6)*x(8)/KABG;

        nonlinear_sdp= [term1;
                    term2;
                    term3;
                    term4;
                    term5;
                    term6;
                    term7;
                    term8;
                    term9];
end