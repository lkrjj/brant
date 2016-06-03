function brant_stat(jobman)

% var_type = 'equal';

out_info.outdir = jobman.out_dir{1};


if isempty(jobman.regressors_tbl)
    error('A table of subject infomation is expected!');
end

if isfield(jobman, 'matrix') && isfield(jobman, 'volume')
    
    vox2vox_ind = jobman.mat_vox2vox;
    
    if jobman.matrix == 1
        if vox2vox_ind == 1
            out_info.data_type = 'stat matrix - voxel to voxel';
        else
            out_info.data_type = 'stat matrix';
        end
        out_info.out_prefix = ''; %jobman.out_prefix;
    elseif jobman.volume == 1
        out_info.data_type = 'stat volume';
        out_info.out_prefix = ''; %jobman.out_prefix;
    else
        error('Unknown file type for statistics!');
    end
    
    fdr_ind = jobman.fdr;
    fdr2_ind = jobman.fdr2;
    bonf_ind = jobman.bonf;
    multi_type = {'FDR', 'FDR2', 'Bonf'};
    multi_ind  = [fdr_ind, fdr2_ind, bonf_ind];
    out_info.p_thr = jobman.p_thr;
    out_info.multi_use = multi_type(multi_ind == 1);
else
    out_info.p_thr = 0.05;
%     net_file = jobman.net_mat{1};
    [net_files, subj_ids_org_tmp] = brant_get_subjs(jobman.input_matrix);
    out_info.data_type = 'stat network';
    out_info.out_prefix = '';
end

discard_bad_ind = jobman.discard_bad_subj;
regressors_tbl = jobman.regressors_tbl{1};
stat_type = jobman.stat_type;

test_ind.one_samp_ind = 0;
test_ind.two_samp_ind = 0;
test_ind.paired_t_ind = 0;
switch(stat_type)
    case 'two sample t-test'
        test_ind.two_samp_ind = 1;
    case 'one sample t-test'
        test_ind.one_samp_ind = 1;
    case 'paired t-test'
        test_ind.paired_t_ind = 1;
    otherwise
        error('ooooo');
end

grp_stat = jobman.grp_stat;
group_est = unique(parse_strs(grp_stat, 'group', 1));
% group_est = unique([group_est_one, group_est_two]);

test_ind.student_t_ind = 1;
test_ind.ranksum_ind = 0;

grp_regr_strs = jobman.regr_strs;
regressors_nm = regexp(grp_regr_strs, '[,;]', 'split'); %#ok<NASGU>

grp_filter = jobman.grp_filter;

if exist(out_info.outdir, 'dir') ~= 7
    mkdir(out_info.outdir);
end

if isempty(regressors_tbl)
    error('A discription table file (*.csv, *.xls) is expected!')    
end

filter_est = parse_strs(grp_filter, 'filter', 0);
reg_est = parse_strs(grp_regr_strs, 'regressors', 0);
score_est = '';

out_info.reg_nm = reg_est;

switch(out_info.data_type)
    case 'stat volume'
        jobman.input_nifti.single_3d = 1;

        mask_fn = jobman.mask{1};
        mask_nii = load_nii(mask_fn);
        size_mask = mask_nii.hdr.dime.dim(2:4);
        mask_hdr = mask_nii.hdr;
        mask_ind = find(mask_nii.img > 0.5);

        [nifti_list, subj_ids_org_tmp] = brant_get_subjs(jobman.input_nifti);
        % spliting filename removal using , or ;
        fn_rmv = regexp(jobman.subj_prefix, '[,;]', 'split');
        subj_ids_org = subj_ids_org_tmp;
        for m = 1:numel(fn_rmv)
            subj_ids_org = strrep(subj_ids_org, fn_rmv{m}, '');
        end
        
        [data_infos, subj_ind, fil_inds, reg_good_subj, corr_good_subj] = parse_subj_info2(regressors_tbl, subj_ids_org, group_est, filter_est, reg_est, score_est, discard_bad_ind);

        fprintf('\n\tLoading nifti images...\n');
        [data_2d_mat, data_tps, nii_hdr] = brant_4D_to_mat_new(nifti_list(subj_ind), mask_ind, 'mat', '');

        out_info.mask_ind = mask_ind;
        out_info.size_mask = size_mask;
        out_info.mask_hdr = mask_hdr;
        
        data_2d_mat = double(data_2d_mat);
        brant_stat_raw(data_2d_mat, grp_stat, filter_est, data_infos, fil_inds, reg_good_subj,...
              test_ind, out_info);
    case 'stat matrix'
        [mat_list, subj_ids_org_tmp] = brant_get_subjs(jobman.input_matrix);
        % spliting filename removal using , or ;
        fn_rmv = regexp(jobman.subj_prefix, '[,;]', 'split');
        subj_ids_org = subj_ids_org_tmp;
        for m = 1:numel(fn_rmv)
            subj_ids_org = strrep(subj_ids_org, fn_rmv{m}, '');
        end
        
        if strcmpi(stat_type, 'paired t-test') == 1
            [data_infos, subj_ind, fil_inds] = parse_subj_info3(regressors_tbl, subj_ids_org, group_est, filter_est);
            reg_good_subj = '';
        else
            [data_infos, subj_ind, fil_inds, reg_good_subj] = parse_subj_info2(regressors_tbl, subj_ids_org, group_est, filter_est, reg_est, score_est, discard_bad_ind);
        end
        
        fprintf('\n\tLoading correlation matrix...\n');
        
        mat_list_good = mat_list(subj_ind);
        corr_mat = cellfun(@load, mat_list_good, 'UniformOutput', false);
        
        if jobman.sym_ind == 1
            % symmetric matrix, use only half value
            num_rois = size(corr_mat{1}, 1);
            corr_ind = triu(true(num_rois), 1);
            if strcmpi(stat_type, 'paired t-test') == 1
                data_2d_mat = cell(1, numel(corr_mat));
                for m = 1:size(corr_mat, 2)
                    data_2d_mat{m} = corr_mat{m}(corr_ind);
                end
            else
                data_2d_mat = cat(3, corr_mat{:});
                data_2d_mat = shiftdim(data_2d_mat, 2);
                data_2d_mat = double(data_2d_mat(:, corr_ind));
            end
            out_info.mat_size = [num_rois, num_rois];
            out_info.corr_ind = corr_ind;
        else
            % arbitary matrix, use all value
            if strcmpi(stat_type, 'paired t-test') == 1
                data_2d_mat = cell(1, numel(corr_mat));
                for m = 1:size(corr_mat, 2)
                    data_2d_mat{m} = corr_mat{m}(:);
                end
            else
                data_2d_mat = cat(3, corr_mat{:});
                data_2d_mat = shiftdim(data_2d_mat, 2);
                data_2d_mat = reshape(data_2d_mat, size(data_2d_mat, 1), []);
            end
            out_info.mat_size = size(corr_mat{1});
            out_info.corr_ind = true(out_info.mat_size);
        end
        clear('corr_mat');
        
        out_info.sym_ind = jobman.sym_ind;
        out_info.num_rois = num_rois;
        brant_stat_raw(data_2d_mat, grp_stat, filter_est, data_infos, fil_inds, reg_good_subj,...
              test_ind, out_info);
          
    case 'stat matrix - voxel to voxel'
        
        jobman.input_matrix.nm_pos = 1;
        jobman.input_matrix.filetype = 'corr_0001.mat';
        [mat_list, subj_ids_org_tmp] = brant_get_subjs(jobman.input_matrix);
        
        mat_sample = load(mat_list{1}, 'num_roi', 'save_pos');
        tot_pieces = mat_sample.save_pos.num_pieces;
        
        % spliting filename removal using , or ;
        fn_rmv = regexp(jobman.subj_prefix, '[,;]', 'split');
        subj_ids_org = subj_ids_org_tmp;
        for m = 1:numel(fn_rmv)
            subj_ids_org = strrep(subj_ids_org, fn_rmv{m}, '');
        end
        [data_infos, subj_ind, fil_inds, reg_good_subj] = parse_subj_info2(regressors_tbl, subj_ids_org, group_est, filter_est, reg_est, score_est, discard_bad_ind);
        fprintf('\tIn total %d blocks, %d correlations/block...\n', tot_pieces, mat_sample.num_roi);
        
        out_info_file = fullfile(out_info.outdir, 'output_fns.mat');
        if exist(out_info_file, 'file') == 2
            delete(out_info_file);
        end
        
        for m = 1:tot_pieces
            
            fprintf('\tCurrent block %d/%d...\n', m, tot_pieces);
            jobman.input_matrix.filetype = num2str(m, 'corr_%04d.mat');
            mat_list = brant_get_subjs(jobman.input_matrix);
            
            out_info.out_prefix = num2str(m, 'stat_%04d_');
            fprintf('\n\tLoading correlation matrix...\n');

            mat_list_good = mat_list(subj_ind);
            corr_mat = cellfun(@(x) load(x, 'corr_z'), mat_list_good);
            data_2d_mat = cat(2, corr_mat.corr_z)';

            corr_tmp = load(mat_list_good{1}, 'num_roi', 'rois_str', 'rois_tag');
            num_rois = corr_tmp.num_roi;
%             out_info.rois_str = corr_tmp.rois_str;
%             out_info.rois_tag = corr_tmp.rois_tag;

%             out_info.corr_ind = corr_ind;
            out_info.mat_size = [num_rois, num_rois];
            out_info.sym_ind = 1;
            clear('corr_mat', 'corr_tmp');

            data_2d_mat = double(data_2d_mat);
            brant_stat_raw(data_2d_mat, grp_stat, filter_est, data_infos, fil_inds, reg_good_subj,...
                  test_ind, out_info);
        end
        
        
%         % merge them maybe?
%         out_fns = load(out_info_file);
%         for m = 1:numel(out_fns.cen_strs)
%             mat_list = cellfun(@(x) fullfile(out_info.outdir, [num2str(m, 'stat_%04d_'), sprintf('%s.mat', out_fns.cen_strs{m})]), 1:tot_pieces, 'UniformOutput', false);
%         end
        
    case 'stat network'
        
        % check options
        check_options = {'net_measure_option', 'thres_spar_ind', 'thres_corr_ind',...
                         'corr_ind', 'spar_ind',...
                         'mst_ind', 'net_type', 'num_node', 'thres_corr_use',...
                         'thres_spar_use', 'thres_nodes_num_spar', 'mat_type'};
        net_mats = cellfun(@(x) load(x, check_options{:}), net_files);
        eq_ind = arrayfun(@(x) isequal(net_mats(1), x), net_mats);
        if any(eq_ind == 0)
            sprintf('%s\n', net_files{eq_ind == 0});
            error('Parameters used in network calculation are different in the following files\ncompared with %s', net_files{1});
        end
        
%         net_mat = load(net_file, 'subj_ids', 'net_measure_option');
        
        % parse fields to run t-test
        sample_mat = net_mats(1);
        field_tmp = fieldnames(sample_mat.net_measure_option);
        struct_ind = cellfun(@(x) ~isstruct(sample_mat.net_measure_option.(x)), field_tmp);
        field_tmp2 = field_tmp(struct_ind);
        sel_ind = cellfun(@(x) sample_mat.net_measure_option.(x) == 1, field_tmp2);
        field_strs = field_tmp2(sel_ind);

        fields_no_test = {'resilience'};
        field_strs = setdiff(field_strs, [fields_no_test, {''}]);

        if isempty(field_strs), return; end
        
        field_strs_good = setdiff(field_strs, '');
        n_field = size(field_strs_good, 1);
        
        % parse data
        fn_rmv = regexp(jobman.subj_prefix, '[,;]', 'split');
        subj_ids_org = subj_ids_org_tmp;
        for m = 1:numel(fn_rmv)
            subj_ids_org = strrep(subj_ids_org, fn_rmv{m}, '');
        end
        [data_infos, subj_ind, fil_inds, reg_good_subj] = parse_subj_info2(regressors_tbl, subj_ids_org, group_est, filter_est, reg_est, '', discard_bad_ind);
        
        % get the data out of mats
        num_subj = sum(subj_ind);
        ind_strs = {'thres_corr_ind', 'thres_spar_ind'};
        thres_type_strs = {'corr', 'spar'};
        data_strs = {'calc_rsts_corr', 'calc_rsts_spar'};
        thres_strs = {'thres_corr_use', 'thres_spar_use'};
        thres_use = cell(2, 1);
        thres_title = cell(2, 1);
        data_load_all = cell(2, 1);
        size_two_thres = zeros(2, 1);
        for n = 1:numel(ind_strs)
            size_two_thres(n) = sample_mat.(ind_strs{n});
            if sample_mat.(ind_strs{n}) == 1
                data_load = cellfun(@(x) load(x, data_strs{n}), net_files(subj_ind));
                data_load_all{n} = cat(2, data_load.(data_strs{n}));
                thres_use{n} = sample_mat.(thres_strs{n});
                thres_title{n} = arrayfun(@(x) num2str(x, [thres_type_strs{n}, '_%.3f']), thres_use{n}, 'UniformOutput', false);
            end
        end
        clear('data_load');
        
        thres_vec = {sample_mat.corr_ind, sample_mat.spar_ind};
        thres_strs = {'threshold of correlation', 'threshold of sparsity'};
        out_suffix = {'corr', 'spar'};
        
        calc_rsts_all = [data_load_all{1}; data_load_all{2}]';
        net_fn_out = fullfile(out_info.outdir, 'network_numeric.xlsx');
        
        
        thres_title_all = [thres_title{1}, thres_title{2}];
        ept_ind = cellfun(@isempty, calc_rsts_all);
        good_ind = ~ept_ind;
        thres_ept = sum(good_ind, 1) ~= num_subj;
        if all(thres_ept)
            error(sprintf('Data of all thresholds are not complete!\nThis situation happens when one or more subject''s correlation matrix don''t survive the threshold.')); %#ok<SPERR>
        end
        if any(thres_ept)
            sprintf('%s\n', thres_title_all{thres_ept});
            warning(sprintf('Data of the above threshold(s) are not complete!\nThis situation happens when one or more subject''s correlation matrix don''t survive the threshold.')); %#ok<SPWRN>
        end
        
        xls_title = ['Name', 'Group', reg_est, thres_title_all];
        
        for m = 1:n_field
            glob_vecs_corr = cellfun(@(x) x.(field_strs_good{m}).global, calc_rsts_all(good_ind));
            glob_vecs_corr_all = nan(size(calc_rsts_all));
            glob_vecs_corr_all(good_ind) = glob_vecs_corr;
            xlswrite(net_fn_out, [xls_title; [data_infos, num2cell([reg_good_subj, glob_vecs_corr_all])]], field_strs_good{m});
            
            if any(thres_ept)
                glob_vecs_corr_all(:, thres_ept) = 0;
            end
            stat_out = brant_stat_raw(glob_vecs_corr_all, grp_stat, filter_est, data_infos, fil_inds, reg_good_subj,...
                      test_ind, out_info);
            
            for p = 1:2
                if size_two_thres(p) == 0, continue; end

                title_tmp = stat_out.constrast_str;
                stat_info_tmp = stat_out.stat_info;

                pval_r = stat_out.p_vec_R(thres_vec{p});
                pval_l = 1 - pval_r;

                mean_grp1 = stat_info_tmp.mean_grp_1_vec(thres_vec{p});
                mean_grp2 = stat_info_tmp.mean_grp_2_vec(thres_vec{p});
                ste_grp1 = stat_info_tmp.std_grp_1_vec(thres_vec{p}) / sqrt(stat_info_tmp.num_grp_1);
                ste_grp2 = stat_info_tmp.std_grp_2_vec(thres_vec{p}) / sqrt(stat_info_tmp.num_grp_2);

                group_est = stat_out.group_est;

                h_fig = plot_rst(thres_strs{p}, field_strs_good{m}, group_est, pval_r, pval_l, thres_use{p}, mean_grp1, ste_grp1, mean_grp2, ste_grp2);
                title(strrep(title_tmp, '_', '\_'));
                set(h_fig, 'Color', [1, 1, 1], 'InvertHardcopy', 'off', 'PaperPositionMode', 'auto');
                out_fn_tmp = fullfile(out_info.outdir, [field_strs_good{m}, '_', out_suffix{p}, '_', title_tmp, '.png']);
                saveas(h_fig, out_fn_tmp);
                fprintf('%s\n', out_fn_tmp);
                delete(h_fig);
            end
        end

    otherwise
        error('Unknown datatype!');
end

fprintf('\tFinished!\n');

function h_fig = plot_rst(x_str, title_str, group_est, p_val_r, p_val_l, thres_x, mean_grp1, ste_grp1, mean_grp2, ste_grp2)

h_fig = figure;
hold('on');
xlabel(x_str);
ylabel(strrep(title_str, '_', ' '), 'FontSize', 12, 'FontWeight', 'bold');

errorbar(thres_x, mean_grp1, ste_grp1, 'r-', 'LineWidth', 2);
errorbar(thres_x, mean_grp2, ste_grp2, 'b-', 'LineWidth', 2);

legend(group_est{1}, group_est{2}, 'location', 'NorthEast');        

x_gca = xlim;
y_gca = ylim;
set(gca, 'Ylim', y_gca + [0, abs(y_gca(2) - y_gca(1)) / 10], 'Xlim', x_gca + [0, abs(x_gca(2) - x_gca(1)) / 7]);
star_loc = y_gca(2) + abs(y_gca(2) - y_gca(1)) / 20;
set(gca, 'box', 'on');

p_ind = p_val_r <= 0.05;
if any(p_ind)
    
    p_ind = p_val_r <= 0.05 & p_val_r > 0.001;
    if any(p_ind)
        plot(thres_x(p_ind), star_loc, 'r*');
    end

    p_ind = p_val_r <= 0.001;
    if any(p_ind)
        plot(thres_x(p_ind), star_loc, 'r^');
    end
end

p_ind = p_val_l <= 0.05;
if any(p_ind)
    
    p_ind = p_val_r <= 0.05 & p_val_r > 0.001;
    if any(p_ind)
        plot(thres_x(p_ind), star_loc, 'b*');
    end
    
    p_ind = p_val_l <= 0.001;
    if any(p_ind)
        plot(thres_x(p_ind), star_loc, 'b^');
    end
end
hold('off');
