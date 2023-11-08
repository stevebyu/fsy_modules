component threadSafe {

	property name="utils" inject;

	variables.dsn = { prod = "fsyweb_pro", dev = "fsyweb_dev", local = "fsyweb_local" };

	public query function countStarted() {
		return QueryExecute(
			"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			select count(*) as started from FSY.DBO.context
			where product = @program
				and context_type = 'Enrollment'
		",
			{},
			{ datasource = variables.dsn.prod }
		);
	}

	public query function countLinked() {
		return QueryExecute(
			"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			select count(*) as linked
			from FSY.DBO.context
			where product = @program
				and context_type = 'Enrollment'
				and context.status = 'Active'
				and prereg_link is not null
		",
			{},
			{ datasource = variables.dsn.prod }
		);
	}

	public query function countJoined() {
		return QueryExecute(
			"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			select count(*) as joined
			from FSY.DBO.context
			where product = @program
				and context_type = 'Enrollment'
				and context.status = 'Active'
				and prereg_link is not null
				and prereg_link not like 'my[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
		",
			{},
			{ datasource = variables.dsn.prod }
		);
	}

	public query function countSession() {
		return QueryExecute(
			"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			select count(context_id) as session
			from (
				select context_id
				from FSY.DBO.context
					inner join session_preference sp on sp.prereg_link = context.prereg_link and sp.program = @program
				where product = @program
					and context_type = 'Enrollment'
				group by context_id
			) data
		",
			{},
			{ datasource = variables.dsn.prod }
		);
	}

	public query function countCompleted() {
		return QueryExecute(
			"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			select count(*) as completed from FSY.DBO.event where event_type = 'preRegReceived'
		",
			{},
			{ datasource = variables.dsn.prod }
		);
	}

	public query function countWithdrawn() {
		return QueryExecute(
			"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			select count(*) as withdrawn from FSY.DBO.context
			where product = @program
				and context_type = 'Enrollment'
				and context.status = 'Canceled'
		",
			{},
			{ datasource = variables.dsn.prod }
		);
	}

	public query function countSelfServeStart() {
		return QueryExecute(
			"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			select count(*) as selfServeStart
			from FSY.DBO.context
			where product = @program
				and context_type = 'Enrollment'
				and person = left(created_by, 8)
		",
			{},
			{ datasource = variables.dsn.prod }
		);
	}

	public query function countAssistedStart() {
		return QueryExecute(
			"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			select count(*) as assistedStart
			from context
				inner join person on person.person_id = left(context.created_by, 8)
				inner join pers_job pj on pj.person = person.person_id
			where context_id in (
				select context_id
				from FSY.DBO.context
				where product = @program
					and context_type = 'Enrollment'
					and person <> left(created_by, 8)
			)
		",
			{},
			{ datasource = variables.dsn.prod }
		);
	}

	public query function countSelfServeCompleted() {
		return QueryExecute(
			"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			select count(*) as selfServeCompleted
			from FSY.DBO.context
				inner join terms_acceptance ta on ta.person = context.person
					and ta.program = context.product
					and left(ta.created_by, 8) = cast(context.person as nvarchar)
			where product = @program
				and context_type = 'Enrollment'
		",
			{},
			{ datasource = variables.dsn.prod }
		);
	}

	public query function countAssistedCompleted() {
		return QueryExecute(
			"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			select count(*) as assistedCompleted
			from context
				inner join terms_acceptance ta on ta.person = context.person
					and ta.program = context.product
				inner join person on cast(person.person_id as nvarchar) = left(ta.created_by, 8)
				inner join pers_job pj on pj.person = person.person_id
			where context_id in (
				select context_id
				from FSY.DBO.context
				where product = @program
					and context_type = 'Enrollment'
					and person <> left(created_by, 8)
			)
		",
			{},
			{ datasource = variables.dsn.prod }
		);
	}

	public struct function dataOverTime() {
		local.range = QueryExecute(
			"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			SELECT prereg_start, sysdatetime() as now from product where product_id = @program
		",
			{},
			{ datasource = variables.dsn.prod }
		)

		local.start = local.range.prereg_start
		local.end = local.range.now
		local.increment = application.preregIncrement
		local.slices = Ceiling(local.end.diff("h", local.start) / local.increment)

		local.json = { "labels" = [], "starts" = [], "completions" = [], "assistedStarts" = [], "selfServeStarts" = [], "parentStarts" = [] }

		for (i = 0; i < local.slices; i++) {
			local.sliceStart = local.start.add("h", i * local.increment)
			local.sliceEnd = local.start.add("h", i * local.increment + local.increment)
			local.json.labels.append(DateTimeFormat(local.sliceStart, "m/d H:nn"))

			// starts
			local.slice = QueryExecute(
				"
				declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

				select count(*) as total
				from FSY.DBO.context
				where product = @program
					and context_type = 'Enrollment'
					and context.created >= :start
					and context.created < :end
			",
				{ start = { value = local.sliceStart, cfsqltype = "timestamp" }, end = { value = local.sliceEnd, cfsqltype = "timestamp" } },
				{ datasource = variables.dsn.prod }
			);

			local.json.starts.append(local.slice.total)

			// completions
			local.slice = QueryExecute(
				"
				declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

				select count(*) as total
				from FSY.DBO.event where event_type = 'preRegReceived'
					and event.occurred >= :start
					and event.occurred < :end
			",
				{ start = { value = local.sliceStart, cfsqltype = "timestamp" }, end = { value = local.sliceEnd, cfsqltype = "timestamp" } },
				{ datasource = variables.dsn.prod }
			);

			local.json.completions.append(local.slice.total)

			// assisted starts
			local.slice = QueryExecute(
				"
				declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

				select count(*) as total
				from context
					inner join person on person.person_id = left(context.created_by, 8)
					inner join pers_job pj on pj.person = person.person_id
				where context_id in (
					select context_id
					from FSY.DBO.context
					where product = @program
						and context_type = 'Enrollment'
						and person <> left(created_by, 8)
						and context.created >= :start
						and context.created < :end
				)
			",
				{ start = { value = local.sliceStart, cfsqltype = "timestamp" }, end = { value = local.sliceEnd, cfsqltype = "timestamp" } },
				{ datasource = variables.dsn.prod }
			);

			local.json.assistedStarts.append(local.slice.total)

			// self-serve starts
			local.slice = QueryExecute(
				"
				declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

				select count(*) as total
				from FSY.DBO.context
				where product = @program
					and context_type = 'Enrollment'
					and person = left(created_by, 8)
					and context.created >= :start
					and context.created < :end
			",
				{ start = { value = local.sliceStart, cfsqltype = "timestamp" }, end = { value = local.sliceEnd, cfsqltype = "timestamp" } },
				{ datasource = variables.dsn.prod }
			);

			local.json.selfServeStarts.append(local.slice.total)
			local.json.parentStarts.append(
				local.json.starts[ local.json.starts.len() ] - local.json.assistedStarts[ local.json.assistedStarts.len() ] - local.json.selfServeStarts[
					local.json.selfServeStarts.len()
				]
			)
		}

		return local.json
	}

	public struct function schedulerData() {
		// Basic overview

		local.preferenceBreakdown = variables.utils.queryToStruct(
			QueryExecute(
				"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			select
			(select count(*) from FSY.DBO.session_preference sp where sp.program = @program) as total_sp_records,
			(select count(*) from FSY.DBO.session_preference sp where sp.program = @program and priority = 1) as p_1,
			(select count(*) from FSY.DBO.session_preference sp where sp.program = @program and priority = 2) as p_2,
			(select count(*) from FSY.DBO.session_preference sp where sp.program = @program and priority = 3) as p_3,
			(select count(*) from FSY.DBO.session_preference sp where sp.program = @program and priority = 4) as p_4,
			(select count(*) from FSY.DBO.session_preference sp where sp.program = @program and priority = 5) as p_5
			",
				{},
				{ datasource = variables.dsn.prod }
			)
		);

		local.linkStats = variables.utils.queryToStruct(
			QueryExecute(
				"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			select
				count(*) as link_preference_size_count, link_preference_size
			from (
				select count(*) link_preference_size
				from Session_Preference sp
				where sp.program = @program
				group by sp.prereg_link
			) data
			group by link_preference_size
			order by link_preference_size
			",
				{},
				{ datasource = variables.dsn.prod }
			)
		);

		local.linkMemberStats = variables.utils.queryToStruct(
			QueryExecute(
				"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			select
				count(link_member_count) as link_member_count_number, link_member_count
			from (
				select count(*) link_member_count
				from context
				where context.product = @program
					and context.context_type = 'Enrollment'
					and context.status <> 'Canceled'
				group by context.prereg_link
			) data
			group by link_member_count
			order by link_member_count
			",
				{},
				{ datasource = variables.dsn.prod }
			)
		);

		local.basicCounts = variables.utils.queryToStruct(
			QueryExecute(
				"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			-- how many people preregistered
			-- how many links were there
			-- how many linked were there
			-- how many singles were there
			select (
					select count(*) from context inner join event on event_object = 'context' and event_object_id = context_id and event_type = 'preRegReceived'
					inner join session_preference sp on sp.prereg_link = context.prereg_link and sp.priority = 1
					where context_type = 'Enrollment' and context.status <> 'Canceled' and context.product = @program
			) as preregistered, (
					select count(distinct sp.prereg_link) from context inner join event on event_object = 'context' and event_object_id = context_id and event_type = 'preRegReceived'
					inner join session_preference sp on sp.prereg_link = context.prereg_link and sp.priority = 1
					where context_type = 'Enrollment' and context.status <> 'Canceled' and context.product = @program and sp.prereg_link not like 'my[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
			) as link_count, (
					select count(*) from context inner join event on event_object = 'context' and event_object_id = context_id and event_type = 'preRegReceived'
					inner join session_preference sp on sp.prereg_link = context.prereg_link and sp.priority = 1
					where context_type = 'Enrollment' and context.status <> 'Canceled' and context.product = @program and sp.prereg_link not like 'my[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
			) as linked, (
					select count(*) from context inner join event on event_object = 'context' and event_object_id = context_id and event_type = 'preRegReceived'
					inner join session_preference sp on sp.prereg_link = context.prereg_link and sp.priority = 1
					where context_type = 'Enrollment' and context.status <> 'Canceled' and context.product = @program and sp.prereg_link like 'my[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
			) as singles
			",
				{},
				{ datasource = variables.dsn.prod }
			)
		);

		// What went right

		local.timedStats = variables.utils.queryToStruct(
			QueryExecute(
				"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			-- how many assignments were made per/minute (average) +
			-- how many people got assigned +
			-- how many assignments were made per/min average +
			-- how long did the scheduler run +
			select
			round(
				cast((select count(context_id) from FSY.DBO.context
					inner join product on product.product_id = context.product and product.master_type = 'Section'
				where product.program = 80000082
					and context_type = 'Enrollment'
					and context.status <> 'Canceled'
				) as float) /
				cast((
				select cast(datediff(second, min(context.created), max(context.created)) as float) / 60.0 from FSY.DBO.context
					inner join product on product.product_id = context.product and product.master_type = 'Section'
				where product.program = 80000082
					and context_type = 'Enrollment'
					and context.status <> 'Canceled'
				) as float), 2
			) as average_assignments_per_minute,
			(
			select count(context_id) as assigned from FSY.DBO.context inner join product on product.product_id = context.product and product.master_type = 'Section'
			where product.program = @program and context_type = 'Enrollment' and context.status <> 'Canceled'
			) as total_assigned,
			(
			select round(cast(datediff(second, min(context.created), max(context.created)) as float) / 60.0, 2) from FSY.DBO.context
				inner join product on product.product_id = context.product and product.master_type = 'Section'
			where product.program = @program
				and context_type = 'Enrollment'
				and context.status <> 'Canceled'
			) as scheduler_duration_minutes
			",
				{},
				{ datasource = variables.dsn.dev }
			)
		);

		local.preregUnassigned = variables.utils.queryToStruct(
			QueryExecute(
				"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			-- how many people who pre-registered didn't get assigned
			select count(context.context_id) as preregistered_unassigned from context inner join event on event_object = 'context' and event_object_id = context_id and event_type = 'preRegReceived'
			inner join session_preference sp on sp.prereg_link = context.prereg_link and sp.priority = 1
			left join (
					context section inner join product product_s on product_s.product_id = section.product and product_s.program = 80000082 and product_s.master_type = 'Section'
			) on section.person = context.person and section.context_type = 'Enrollment' and section.status <> 'Canceled'
			where context.context_type = 'Enrollment' and context.status <> 'Canceled' and context.product = 80000082 and section.context_id is null
			",
				{},
				{ datasource = variables.dsn.dev }
			)
		);


		local.assignedByChoice = variables.utils.queryToStruct(
			QueryExecute(
				"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			-- how many got their 1st choice (2nd, 3rd, etc.)
			select
			(
					select count(context.context_id) from context inner join product on product_id = product and product.master_type = 'Section' inner join context context_p on context_p.person = context.person and context_p.product = product.program
					inner join session_preference sp on sp.prereg_link = context_p.prereg_link and sp.program = product.program and sp.priority = 1
					inner join pm_session on pm_session.product = context.product
					where product.program = 80000082 and cast(pm_session.participant_start_date as date) = sp.start_date and pm_session.pm_location = sp.pm_location and context.context_type = 'Enrollment' and context.status <> 'Canceled'
			) as got_1,
			(
					select count(context.context_id) from context inner join product on product_id = product and product.master_type = 'Section' inner join context context_p on context_p.person = context.person and context_p.product = product.program
					inner join session_preference sp on sp.prereg_link = context_p.prereg_link and sp.program = product.program and sp.priority = 2
					inner join pm_session on pm_session.product = context.product
					where product.program = 80000082 and cast(pm_session.participant_start_date as date) = sp.start_date and pm_session.pm_location = sp.pm_location and context.context_type = 'Enrollment' and context.status <> 'Canceled'
			) as got_2,
			(
					select count(context.context_id) from context inner join product on product_id = product and product.master_type = 'Section' inner join context context_p on context_p.person = context.person and context_p.product = product.program
					inner join session_preference sp on sp.prereg_link = context_p.prereg_link and sp.program = product.program and sp.priority = 3
					inner join pm_session on pm_session.product = context.product
					where product.program = 80000082 and cast(pm_session.participant_start_date as date) = sp.start_date and pm_session.pm_location = sp.pm_location and context.context_type = 'Enrollment' and context.status <> 'Canceled'
			) as got_3,
			(
					select count(context.context_id) from context inner join product on product_id = product and product.master_type = 'Section' inner join context context_p on context_p.person = context.person and context_p.product = product.program
					inner join session_preference sp on sp.prereg_link = context_p.prereg_link and sp.program = product.program and sp.priority = 4
					inner join pm_session on pm_session.product = context.product
					where product.program = 80000082 and cast(pm_session.participant_start_date as date) = sp.start_date and pm_session.pm_location = sp.pm_location and context.context_type = 'Enrollment' and context.status <> 'Canceled'
			) as got_4,
			(
					select count(context.context_id) from context inner join product on product_id = product and product.master_type = 'Section' inner join context context_p on context_p.person = context.person and context_p.product = product.program
					inner join session_preference sp on sp.prereg_link = context_p.prereg_link and sp.program = product.program and sp.priority = 5
					inner join pm_session on pm_session.product = context.product
					where product.program = 80000082 and cast(pm_session.participant_start_date as date) = sp.start_date and pm_session.pm_location = sp.pm_location and context.context_type = 'Enrollment' and context.status <> 'Canceled'
			) as got_5
			",
				{},
				{ datasource = variables.dsn.dev }
			)
		);

		local.fullSessions = variables.utils.queryToStruct(
			QueryExecute(
				"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			-- which sessions got filled up
			select *, case when (max_enroll_f - enrolled_f = 0) and (max_enroll_m - enrolled_m = 0) then 1 else 0 end as full_session
			from (
			select
					section.title,
					option_f.max_enroll as max_enroll_f,
					option_m.max_enroll as max_enroll_m,
					(
							select count(context.context_id) from context inner join product on product.product_id = context.product and product.housing_type = 'Female' and context.context_type = 'Enrollment' and context.status <> 'Canceled'
							and product.product_id = option_f.product_id
					) as enrolled_f,
					(
							select count(context.context_id) from context inner join product on product.product_id = context.product and product.housing_type = 'Male' and context.context_type = 'Enrollment' and context.status <> 'Canceled'
							and product.product_id = option_m.product_id
					) as enrolled_m
			from FSY.DBO.product section
			inner join option_item oi_f ON oi_f.section = section.product_id inner join product option_f on option_f.product_id = oi_f.item and option_f.housing_type = 'Female'
			inner join option_item oi_m ON oi_m.section = section.product_id inner join product option_m on option_m.product_id = oi_m.item and option_m.housing_type = 'Male'
			where section.program = 80000082 and section.master_type = 'Section' and section.status <> 'Canceled'
			) data
			",
				{},
				{ datasource = variables.dsn.dev }
			)
		);

		local.fullSessionCount = variables.utils.queryToStruct(
			QueryExecute(
				"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			-- how many sessions got filled up
			select sum(full_session) as num_full_sessions
			from (
					select *, case when (max_enroll_f - enrolled_f = 0) and (max_enroll_m - enrolled_m = 0) then 1 else 0 end as full_session
					from (
					select
							section.title,
							option_f.max_enroll as max_enroll_f,
							option_m.max_enroll as max_enroll_m,
							(
									select count(context.context_id) from context inner join product on product.product_id = context.product and product.housing_type = 'Female' and context.context_type = 'Enrollment' and context.status <> 'Canceled'
									and product.product_id = option_f.product_id
							) as enrolled_f,
							(
									select count(context.context_id) from context inner join product on product.product_id = context.product and product.housing_type = 'Male' and context.context_type = 'Enrollment' and context.status <> 'Canceled'
									and product.product_id = option_m.product_id
							) as enrolled_m
					from FSY.DBO.product section
					inner join option_item oi_f ON oi_f.section = section.product_id inner join product option_f on option_f.product_id = oi_f.item and option_f.housing_type = 'Female'
					inner join option_item oi_m ON oi_m.section = section.product_id inner join product option_m on option_m.product_id = oi_m.item and option_m.housing_type = 'Male'
					where section.program = 80000082 and section.master_type = 'Section' and section.status <> 'Canceled'
					) data
			) data2
			",
				{},
				{ datasource = variables.dsn.dev }
			)
		);

		local.fullPlaceTimes = variables.utils.queryToStruct(
			QueryExecute(
				"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			-- which place/times got filled up
			select pm_location, start_date, count(pm_session_id) as sessions_at_place_time, sum(full_session) as full_sessions
			from (
					select *, case when (max_enroll_f - enrolled_f = 0) and (max_enroll_m - enrolled_m = 0) then 1 else 0 end as full_session
					from (
					select
							pm_session_id,
							pm_session.pm_location,
							cast(pm_session.participant_start_date as date) as start_date,
							option_f.max_enroll as max_enroll_f,
							option_m.max_enroll as max_enroll_m,
							(
									select count(context.context_id) from context inner join product on product.product_id = context.product and product.housing_type = 'Female' and context.context_type = 'Enrollment' and context.status <> 'Canceled'
									and product.product_id = option_f.product_id
							) as enrolled_f,
							(
									select count(context.context_id) from context inner join product on product.product_id = context.product and product.housing_type = 'Male' and context.context_type = 'Enrollment' and context.status <> 'Canceled'
									and product.product_id = option_m.product_id
							) as enrolled_m
					from FSY.DBO.product section
					inner join pm_session ON pm_session.product = section.product_id
					inner join option_item oi_f ON oi_f.section = section.product_id inner join product option_f on option_f.product_id = oi_f.item and option_f.housing_type = 'Female'
					inner join option_item oi_m ON oi_m.section = section.product_id inner join product option_m on option_m.product_id = oi_m.item and option_m.housing_type = 'Male'
					where section.program = 80000082 and section.master_type = 'Section' and section.status <> 'Canceled'
					) data
			) data2
			group by pm_location, start_date
			",
				{},
				{ datasource = variables.dsn.dev }
			)
		);

		local.fullPlaceTimesCounts = variables.utils.queryToStruct(
			QueryExecute(
				"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			-- how many place/times got filled up vs still have space
			select
					sum(case when sessions_at_place_time - full_sessions = 0 then 1 else 0 end) as full_place_times,
					sum(case when sessions_at_place_time - full_sessions > 0 then 1 else 0 end) as place_times_with_space
			from (
					select pm_location, start_date, count(pm_session_id) as sessions_at_place_time, sum(full_session) as full_sessions
					from (
							select *, case when (max_enroll_f - enrolled_f = 0) and (max_enroll_m - enrolled_m = 0) then 1 else 0 end as full_session
							from (
							select
									pm_session_id,
									pm_session.pm_location,
									cast(pm_session.participant_start_date as date) as start_date,
									option_f.max_enroll as max_enroll_f,
									option_m.max_enroll as max_enroll_m,
									(
											select count(context.context_id) from context inner join product on product.product_id = context.product and product.housing_type = 'Female' and context.context_type = 'Enrollment' and context.status <> 'Canceled'
											and product.product_id = option_f.product_id
									) as enrolled_f,
									(
											select count(context.context_id) from context inner join product on product.product_id = context.product and product.housing_type = 'Male' and context.context_type = 'Enrollment' and context.status <> 'Canceled'
											and product.product_id = option_m.product_id
									) as enrolled_m
							from FSY.DBO.product section
							inner join pm_session ON pm_session.product = section.product_id
							inner join option_item oi_f ON oi_f.section = section.product_id inner join product option_f on option_f.product_id = oi_f.item and option_f.housing_type = 'Female'
							inner join option_item oi_m ON oi_m.section = section.product_id inner join product option_m on option_m.product_id = oi_m.item and option_m.housing_type = 'Male'
							where section.program = 80000082 and section.master_type = 'Section' and section.status <> 'Canceled'
							) data
					) data2
					group by pm_location, start_date
			) data3
			",
				{},
				{ datasource = variables.dsn.dev }
			)
		);

		local.singleGenderFull = variables.utils.queryToStruct(
			QueryExecute(
				"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			-- which sessions have one gender full but not the other
			select
					*,
					case when max_enroll_f - enrolled_f = 0 then 1 else 0 end as full_f,
					case when max_enroll_m - enrolled_m = 0 then 1 else 0 end as full_m,
					case when (
							(max_enroll_f - enrolled_f > 0 and max_enroll_m - enrolled_m = 0)
							or (max_enroll_f - enrolled_f = 0 and max_enroll_m - enrolled_m > 0)
					) then 1 else 0 end as single_gender_full
			from (
			select
					section.title,
					option_f.max_enroll as max_enroll_f,
					option_m.max_enroll as max_enroll_m,
					(
							select count(context.context_id) from context inner join product on product.product_id = context.product and product.housing_type = 'Female' and context.context_type = 'Enrollment' and context.status <> 'Canceled'
							and product.product_id = option_f.product_id
					) as enrolled_f,
					(
							select count(context.context_id) from context inner join product on product.product_id = context.product and product.housing_type = 'Male' and context.context_type = 'Enrollment' and context.status <> 'Canceled'
							and product.product_id = option_m.product_id
					) as enrolled_m
			from FSY.DBO.product section
			inner join option_item oi_f ON oi_f.section = section.product_id inner join product option_f on option_f.product_id = oi_f.item and option_f.housing_type = 'Female'
			inner join option_item oi_m ON oi_m.section = section.product_id inner join product option_m on option_m.product_id = oi_m.item and option_m.housing_type = 'Male'
			where section.program = 80000082 and section.master_type = 'Section' and section.status <> 'Canceled'
			) data
			",
				{},
				{ datasource = variables.dsn.dev }
			)
		);

		local.singleGenderFullCount = variables.utils.queryToStruct(
			QueryExecute(
				"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			-- how many sessions have one gender full but not the other
			select sum(single_gender_full) as single_gender_full
			from (
					select
							*,
							case when max_enroll_f - enrolled_f = 0 then 1 else 0 end as full_f,
							case when max_enroll_m - enrolled_m = 0 then 1 else 0 end as full_m,
							case when (
									(max_enroll_f - enrolled_f > 0 and max_enroll_m - enrolled_m = 0)
									or (max_enroll_f - enrolled_f = 0 and max_enroll_m - enrolled_m > 0)
							) then 1 else 0 end as single_gender_full
					from (
					select
							section.title,
							option_f.max_enroll as max_enroll_f,
							option_m.max_enroll as max_enroll_m,
							(
									select count(context.context_id) from context inner join product on product.product_id = context.product and product.housing_type = 'Female' and context.context_type = 'Enrollment' and context.status <> 'Canceled'
									and product.product_id = option_f.product_id
							) as enrolled_f,
							(
									select count(context.context_id) from context inner join product on product.product_id = context.product and product.housing_type = 'Male' and context.context_type = 'Enrollment' and context.status <> 'Canceled'
									and product.product_id = option_m.product_id
							) as enrolled_m
					from FSY.DBO.product section
					inner join option_item oi_f ON oi_f.section = section.product_id inner join product option_f on option_f.product_id = oi_f.item and option_f.housing_type = 'Female'
					inner join option_item oi_m ON oi_m.section = section.product_id inner join product option_m on option_m.product_id = oi_m.item and option_m.housing_type = 'Male'
					where section.program = 80000082 and section.master_type = 'Section' and section.status <> 'Canceled'
					) data
			) data2
			",
				{},
				{ datasource = variables.dsn.dev }
			)
		);


		local.linksPlacedCounts = variables.utils.queryToStruct(
			QueryExecute(
				"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			-- how many link groups (not my's) were placed vs not placed vs partially placed
			/* */
			select sum(placed) as placed, sum(unplaced) as unplaced, sum(partially_placed) as partially_placed
			from (
			/* */
			select
					prereg_link,
					sum(case when group_size = group_placed then 1 else 0 end) as placed,
					sum(case when group_placed = 0 then 1 else 0 end) as unplaced,
					sum(case when group_size <> group_placed and group_placed > 0 then 1 else 0 end) as partially_placed
			from (
					select
									context.prereg_link,
									count(context.prereg_link) as group_size,
									count(section.context_id) as group_placed
							from FSY.DBO.context
									inner join event on event.event_object = 'context' and event.event_object_id = context.context_id and event.event_type = 'preRegReceived'
									inner join session_preference sp_1 on sp_1.prereg_link = context.prereg_link and sp_1.priority = 1 -- not used other than to make sure they had at least one
									left join (
											session_preference sp
											inner join pm_session ps on ps.pm_location = sp.pm_location and cast(ps.PARTICIPANT_START_DATE as date) = sp.start_date
											inner join context section on section.product = ps.product and section.status <> 'Canceled' and section.context_type = 'Enrollment'
									) on sp.prereg_link = context.prereg_link and section.person = context.person
							where context.product = 80000082
									and context.context_type = 'Enrollment'
									and context.status <> 'Canceled'
									and context.prereg_link not like 'my[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
							group by context.prereg_link
			) data
			group by prereg_link
			/* */
			) data2
			/* */
			",
				{},
				{ datasource = variables.dsn.dev }
			)
		);


		local.assignedByGenderCounts = variables.utils.queryToStruct(
			QueryExecute(
				"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			-- how many males were placed, how many females
			select
					sum(case when person.gender = 'F' then 1 else 0 end) as placed_f,
					sum(case when person.gender = 'M' then 1 else 0 end) as placed_m,
					count(section.context_id) as placed_total
			from FSY.DBO.context
					inner join person on person.person_id = context.person
					inner join event on event.event_object = 'context' and event.event_object_id = context.context_id and event.event_type = 'preRegReceived'
					inner join session_preference sp on sp.prereg_link = context.prereg_link
					inner join pm_session ps on ps.pm_location = sp.pm_location and cast(ps.PARTICIPANT_START_DATE as date) = sp.start_date
					inner join context section on section.product = ps.product and section.status <> 'Canceled' and section.context_type = 'Enrollment' and section.person = context.person
			where context.product = 80000082
					and context.context_type = 'Enrollment'
					and context.status <> 'Canceled'
			",
				{},
				{ datasource = variables.dsn.dev }
			)
		);

		local.assignedByLinkType = variables.utils.queryToStruct(
			QueryExecute(
				"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			-- how many males were placed, how many females
			select
					(
						select count(program_c.context_id)
						from context program_c
							inner join event on event.event_object = 'context' and event.event_object_id = program_c.context_id and event.event_type = 'preRegReceived'
							left join (
								context section
								inner join product on product.product_id = section.product and product.program = @program and product.master_type = 'Section'
							) on section.person = program_c.person and section.status <> 'Canceled' and section.context_type = 'Enrollment'
						where program_c.product = @program
							and program_c.context_type = 'Enrollment'
							and program_c.status <> 'Canceled'
							and exists(
								select sp.prereg_link from session_preference sp where sp.program = @program and sp.prereg_link = program_c.prereg_link
							)
							and program_c.prereg_link like 'my[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
							and section.context_id is not null
					) AS assigned_my,
					(
						select count(program_c.context_id)
						from context program_c
							inner join event on event.event_object = 'context' and event.event_object_id = program_c.context_id and event.event_type = 'preRegReceived'
							left join (
								context section
								inner join product on product.product_id = section.product and product.program = @program and product.master_type = 'Section'
							) on section.person = program_c.person and section.status <> 'Canceled' and section.context_type = 'Enrollment'
						where program_c.product = @program
							and program_c.context_type = 'Enrollment'
							and program_c.status <> 'Canceled'
							and exists(
								select sp.prereg_link from session_preference sp where sp.program = @program and sp.prereg_link = program_c.prereg_link
							)
							and program_c.prereg_link not like 'my[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
							and section.context_id is not null
					) AS assigned_linked,
					(
						select count(program_c.context_id)
						from context program_c
							inner join event on event.event_object = 'context' and event.event_object_id = program_c.context_id and event.event_type = 'preRegReceived'
							left join (
								context section
								inner join product on product.product_id = section.product and product.program = @program and product.master_type = 'Section'
							) on section.person = program_c.person and section.status <> 'Canceled' and section.context_type = 'Enrollment'
						where program_c.product = @program
							and program_c.context_type = 'Enrollment'
							and program_c.status <> 'Canceled'
							and exists(
								select sp.prereg_link from session_preference sp where sp.program = @program and sp.prereg_link = program_c.prereg_link
							)
							and program_c.prereg_link like 'my[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
							and section.context_id is null
					) AS unassigned_my,
					(
						select count(program_c.context_id)
						from context program_c
							inner join event on event.event_object = 'context' and event.event_object_id = program_c.context_id and event.event_type = 'preRegReceived'
							left join (
								context section
								inner join product on product.product_id = section.product and product.program = @program and product.master_type = 'Section'
							) on section.person = program_c.person and section.status <> 'Canceled' and section.context_type = 'Enrollment'
						where program_c.product = @program
							and program_c.context_type = 'Enrollment'
							and program_c.status <> 'Canceled'
							and exists(
								select sp.prereg_link from session_preference sp where sp.program = @program and sp.prereg_link = program_c.prereg_link
							)
							and program_c.prereg_link not like 'my[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
							and section.context_id is null
					) AS unassigned_linked
			",
				{},
				{ datasource = variables.dsn.dev }
			)
		);

		local.assignedByReservationType = variables.utils.queryToStruct(
			QueryExecute(
				"
			declare @program numeric(8) = (select value from cntl_value where control = 'current_fsy_program')

			-- how many were placed or not placed, by reservation or not
			select
					(
						select isnull(sum(contexts), 0)
						from (
							select count(distinct program_c.context_id) as contexts
							from context program_c
								inner join event on event.event_object = 'context' and event.event_object_id = program_c.context_id and event.event_type = 'preRegReceived'
								inner join fsy_unit ward ON ward.unit_number = cast(program_c.lds_unit_no as varchar)
								inner join fsy_unit stake ON stake.unit_number = ward.parent
								left join session_preference sp on sp.program = program_c.product and sp.prereg_link = program_c.prereg_link and sp.priority = 1
								left join (
									context section
									inner join product on product.product_id = section.product and product.program = @program and product.master_type = 'Section'
								) on section.person = program_c.person and section.status <> 'Canceled' and section.context_type = 'Enrollment'
								left join (
										fsy_session_unit fsu_w
										inner join pm_session pm_session_w on pm_session_w.pm_session_id = fsu_w.pm_session
										inner join product product_w on product_w.product_id = pm_session_w.product
								) on fsu_w.fsy_unit = ward.unit_number and product_w.program = program_c.product
								left join (
										fsy_session_unit fsu_s
										inner join pm_session pm_session_s on pm_session_s.pm_session_id = fsu_s.pm_session
										inner join product product_s on product_s.product_id = pm_session_s.product
								) on fsu_s.fsy_unit = stake.unit_number and product_s.program = program_c.product
							where program_c.product = @program
								and program_c.context_type = 'Enrollment'
								and program_c.status <> 'Canceled'
								and sp.prereg_link is not null
								and (
									(fsu_w.pm_session is null and (fsu_s.male is not null or fsu_s.female is not null))
									or (fsu_w.pm_session is not null and (fsu_w.male is not null or fsu_w.female is not null))
								)
								and section.context_id is not null
							group by program_c.context_id
            ) data
					) AS assigned_reserved,
					(
						select isnull(sum(contexts), 0)
						from (
							select count(distinct program_c.context_id) as contexts
							from context program_c
								inner join event on event.event_object = 'context' and event.event_object_id = program_c.context_id and event.event_type = 'preRegReceived'
								inner join fsy_unit ward ON ward.unit_number = cast(program_c.lds_unit_no as varchar)
								inner join fsy_unit stake ON stake.unit_number = ward.parent
								left join session_preference sp on sp.program = program_c.product and sp.prereg_link = program_c.prereg_link and sp.priority = 1
								left join (
									context section
									inner join product on product.product_id = section.product and product.program = @program and product.master_type = 'Section'
								) on section.person = program_c.person and section.status <> 'Canceled' and section.context_type = 'Enrollment'
								left join (
										fsy_session_unit fsu_w
										inner join pm_session pm_session_w on pm_session_w.pm_session_id = fsu_w.pm_session
										inner join product product_w on product_w.product_id = pm_session_w.product
								) on fsu_w.fsy_unit = ward.unit_number and product_w.program = program_c.product
								left join (
										fsy_session_unit fsu_s
										inner join pm_session pm_session_s on pm_session_s.pm_session_id = fsu_s.pm_session
										inner join product product_s on product_s.product_id = pm_session_s.product
								) on fsu_s.fsy_unit = stake.unit_number and product_s.program = program_c.product
							where program_c.product = @program
								and program_c.context_type = 'Enrollment'
								and program_c.status <> 'Canceled'
								and sp.prereg_link is not null
								and not (
									(fsu_w.pm_session is null and (fsu_s.male is not null or fsu_s.female is not null))
									or (fsu_w.pm_session is not null and (fsu_w.male is not null or fsu_w.female is not null))
								)
								and section.context_id is not null
							group by program_c.context_id
            ) data
					) AS assigned_regular,
					(
						select sum(contexts)
						from (
							select count(distinct program_c.context_id) as contexts
							from context program_c
								inner join event on event.event_object = 'context' and event.event_object_id = program_c.context_id and event.event_type = 'preRegReceived'
								inner join fsy_unit ward ON ward.unit_number = cast(program_c.lds_unit_no as varchar)
								inner join fsy_unit stake ON stake.unit_number = ward.parent
								left join session_preference sp on sp.program = program_c.product and sp.prereg_link = program_c.prereg_link and sp.priority = 1
								left join (
									context section
									inner join product on product.product_id = section.product and product.program = @program and product.master_type = 'Section'
								) on section.person = program_c.person and section.status <> 'Canceled' and section.context_type = 'Enrollment'
								left join (
										fsy_session_unit fsu_w
										inner join pm_session pm_session_w on pm_session_w.pm_session_id = fsu_w.pm_session
										inner join product product_w on product_w.product_id = pm_session_w.product
								) on fsu_w.fsy_unit = ward.unit_number and product_w.program = program_c.product
								left join (
										fsy_session_unit fsu_s
										inner join pm_session pm_session_s on pm_session_s.pm_session_id = fsu_s.pm_session
										inner join product product_s on product_s.product_id = pm_session_s.product
								) on fsu_s.fsy_unit = stake.unit_number and product_s.program = program_c.product
							where program_c.product = @program
								and program_c.context_type = 'Enrollment'
								and program_c.status <> 'Canceled'
								and sp.prereg_link is not null
								and (
									(fsu_w.pm_session is null and (fsu_s.male is not null or fsu_s.female is not null))
									or (fsu_w.pm_session is not null and (fsu_w.male is not null or fsu_w.female is not null))
								)
								and section.context_id is null
							group by program_c.context_id
            ) data
					) AS unassigned_reserved,
					(
						select sum(contexts)
						from (
							select count(distinct program_c.context_id) as contexts
							from context program_c
								inner join event on event.event_object = 'context' and event.event_object_id = program_c.context_id and event.event_type = 'preRegReceived'
								inner join fsy_unit ward ON ward.unit_number = cast(program_c.lds_unit_no as varchar)
								inner join fsy_unit stake ON stake.unit_number = ward.parent
								left join session_preference sp on sp.program = program_c.product and sp.prereg_link = program_c.prereg_link and sp.priority = 1
								left join (
									context section
									inner join product on product.product_id = section.product and product.program = @program and product.master_type = 'Section'
								) on section.person = program_c.person and section.status <> 'Canceled' and section.context_type = 'Enrollment'
								left join (
										fsy_session_unit fsu_w
										inner join pm_session pm_session_w on pm_session_w.pm_session_id = fsu_w.pm_session
										inner join product product_w on product_w.product_id = pm_session_w.product
								) on fsu_w.fsy_unit = ward.unit_number and product_w.program = program_c.product
								left join (
										fsy_session_unit fsu_s
										inner join pm_session pm_session_s on pm_session_s.pm_session_id = fsu_s.pm_session
										inner join product product_s on product_s.product_id = pm_session_s.product
								) on fsu_s.fsy_unit = stake.unit_number and product_s.program = program_c.product
							where program_c.product = @program
								and program_c.context_type = 'Enrollment'
								and program_c.status <> 'Canceled'
								and sp.prereg_link is not null
								and not (
									(fsu_w.pm_session is null and (fsu_s.male is not null or fsu_s.female is not null))
									or (fsu_w.pm_session is not null and (fsu_w.male is not null or fsu_w.female is not null))
								)
								and section.context_id is null
							group by program_c.context_id
            ) data
					) AS unassigned_regular
			",
				{},
				{ datasource = variables.dsn.dev }
			)
		);

		// What went wrong

		return {
			"preferenceBreakdown" = local.preferenceBreakdown,
			"timedStats" = local.timedStats,
			"linkStats" = local.linkStats,
			"basicCounts" = local.basicCounts,
			"preregUnassigned" = local.preregUnassigned,
			"assignedByChoice" = local.assignedByChoice,
			"fullSessions" = local.fullSessions,
			"fullSessionCount" = local.fullSessionCount,
			"fullPlaceTimes" = local.fullPlaceTimes,
			"fullPlaceTimesCounts" = local.fullPlaceTimesCounts,
			"singleGenderFull" = local.singleGenderFull,
			"singleGenderFullCount" = local.singleGenderFullCount,
			"linksPlacedCounts" = local.linksPlacedCounts,
			"assignedByGenderCounts" = local.assignedByGenderCounts,
			"assignedByLinkType" = local.assignedByLinkType,
			"assignedByReservationType" = local.assignedByReservationType,
			"linkMemberStats" = local.linkMemberStats
		}
	}

	// Testing utils

	/*
	+ create program
	+ set cntl_value to created program
	+ create section product with m/f housing linked via option_item/group
	+ create person
	+ create prereg program context with a given prereg_link value
	+ create preRegReceived event for program context
	+ create pm_location
	+ create session_preference records for a given prereg_link value
	+ create ward
	+ create stake
	create pm_session
	create fsy_session_unit records for assignments (optionally w/ reservation numbers)
	teardown
	*/

	public numeric function createProgram() {
		QueryExecute(
			"
			insert into product (
				status,
				short_title,
				title,
				department,
				product_type,
				master_type,
				include_in_enrollment_total,
				created_by
			)
			select
				status,
				concat(short_title, '_1333'),
				concat(title, '_1333'),
				department,
				product_type,
				master_type,
				include_in_enrollment_total,
				created_by
			from product where product_id = 80000082
		",
			{},
			{ datasource = variables.dsn.local, result = "local.result" }
		);

		return local.result.generatedkey;
	}

	public void function setControlValueToCreatedProgram(
		numeric product_id
	) {
		QueryExecute(
			"
			update cntl_value set value = :product_id, updated_by = 'FSY-1333' where control = 'current_fsy_program'
		",
			{ product_id = arguments.product_id },
			{ datasource = variables.dsn.local }
		);
	}

	public struct function createFullSection(
		required numeric program,
		numeric female = 10,
		numeric male = 10
	) {
		local.data = {}

		// ensure unique short_title
		local.result = QueryExecute(
			"
			select top 1 title
			from product
			where master_type = 'Section'
				and short_title like '%_1333'
			order by created desc
		",
			{},
			{ datasource = variables.dsn.local }
		);

		if (local.result.recordCount == 0) local.next = 1;
		else {
			local.match = ReFind("Section_(\d+)_1333", local.result.title)
			local.next = Mid(local.result.title, local.match.pos[ 1 ], local.match.len[ 1 ])
		}

		// section
		QueryExecute(
			"
			insert into product (
				status,
				short_title,
				title,
				department,
				product_type,
				master_type,
				program,
				include_in_enrollment_total,
				created_by
			)
			select
				'Active',
				concat('Section_', :next, '_1333'),
				concat('Section_', :next, '_1333'),
				department,
				product_type,
				'Section',
				:program,
				include_in_enrollment_total,
				created_by
			from product where product_id = 80000082
		",
			{ next = local.next, program = arguments.program },
			{ datasource = variables.dsn.local, result = "local.result" }
		)

		local.data.section = local.result.generatedKey

		// female housing
		QueryExecute(
			"
			insert into product (
				status,
				short_title,
				title,
				department,
				product_type,
				master_type,
				option_type,
				housing_type,
				max_space,
				max_enroll,
				program,
				include_in_enrollment_total,
				created_by
			)
			select
				'Active',
				concat('FemaleHousing_', :next, '_1333'),
				concat('FemaleHousing_', :next, '_1333'),
				department,
				product_type,
				'Option',
				'Housing',
				'Female',
				:max_enroll,
				:max_enroll,
				:program,
				include_in_enrollment_total,
				created_by
			from product where product_id = 80000082
		",
			{ next = local.next, program = arguments.program, max_enroll = arguments.female },
			{ datasource = variables.dsn.local, result = "local.result" }
		)

		local.data.female = local.result.generatedKey

		// male housing
		QueryExecute(
			"
			insert into product (
				status,
				short_title,
				title,
				department,
				product_type,
				master_type,
				option_type,
				housing_type,
				max_space,
				max_enroll,
				program,
				include_in_enrollment_total,
				created_by
			)
			select
				'Active',
				concat('MaleHousing_', :next, '_1333'),
				concat('MaleHousing_', :next, '_1333'),
				department,
				product_type,
				'Option',
				'Housing',
				'Male',
				:max_enroll,
				:max_enroll,
				:program,
				include_in_enrollment_total,
				created_by
			from product where product_id = 80000082
		",
			{ next = local.next, program = arguments.program, max_enroll = arguments.male },
			{ datasource = variables.dsn.local, result = "local.result" }
		)

		local.data.male = local.result.generatedKey

		// option group
		QueryExecute(
			"
			insert into option_group (
				section,
				name,
				min_choice,
				max_choice,
				created_by
			)
			select
				:section,
				'Housing',
				1,
				1,
				created_by
			from product where product_id = 80000082
		",
			{ section = local.data.section },
			{ datasource = variables.dsn.local, result = "local.result" }
		)

		local.data.optionGroup = local.result.recordcount > 0

		// female option_item
		QueryExecute(
			"
			insert into option_item (
				section,
				name,
				item,
				created_by
			)
			select
				:section,
				'Housing',
				:item,
				created_by
			from product where product_id = 80000082
		",
			{ section = local.data.section, item = local.data.female },
			{ datasource = variables.dsn.local, result = "local.result" }
		)

		local.data.optionItemF = local.result.recordcount > 0

		// male option_item
		QueryExecute(
			"
			insert into option_item (
				section,
				name,
				item,
				created_by
			)
			select
				:section,
				'Housing',
				:item,
				created_by
			from product where product_id = 80000082
		",
			{ section = local.data.section, item = local.data.male },
			{ datasource = variables.dsn.local, result = "local.result" }
		)

		local.data.optionItemM = local.result.recordcount > 0

		return local.data
	}

	public numeric function createPerson(
		required string gender
	) {
		QueryExecute(
			"
			insert into person (first_name, last_name, gender, birthdate, lds_account_id, created_by)
			values ('First_1333', 'Last_1333', :gender, '2008-01-01', :church_id, 'FSY-1333')
		",
			{ gender = arguments.gender, church_id = "#Floor(Rand() * 100000000)##Floor(Rand() * 100000000)#" },
			{ datasource = variables.dsn.local, result = "local.result" }
		);

		return local.result.generatedKey
	}

	public numeric function createProgramContext(
		required numeric program,
		required numeric person,
		string prereg_link = ""
	) {
		QueryExecute(
			"
			insert into context (person, product, context_type, status, pending_status, prereg_link, created_by)
			values (:person, :product, 'Enrollment', 'Reserved', 'Active', :prereg_link, 'FSY-1333')
		",
			{ person = arguments.person, product = arguments.program, prereg_link = arguments.prereg_link },
			{ datasource = variables.dsn.local, result = "local.result" }
		);

		if (arguments.prereg_link == "")
			QueryExecute(
				"
				update context set prereg_link = :prereg_link, updated_by = 'FSY-1333' where context_id = :context_id
			",
				{ prereg_link = "my#local.result.generatedkey#", context_id = local.result.generatedkey },
				{ datasource = variables.dsn.local }
			);

		return local.result.generatedkey
	}

	public void function createPreRegReceivedEvent(
		required numeric context_id
	) {
		QueryExecute(
			"
			insert into event (event_object, event_object_id, event_type) values ('CONTEXT', :context_id, 'preRegReceived')
		",
			{ context_id = arguments.context_id },
			{ datasource = variables.dsn.local }
		);
	}

	public numeric function createPMLocation() {
		// TODO: see if country is necessary - hopefully that'll just be on the product ¯\_(ツ)_/¯
		QueryExecute(
			"
			insert into pm_location (name, created_by) values ('This is the place', 'FSY-1333')
		",
			{},
			{ datasource = variables.dsn.local, result = "local.result" }
		);

		return local.result.generatedkey
	}

	public void function createSessionPreference(
		required numeric program,
		required string prereg_link,
		required numeric pm_location,
		required string start_date,
		numeric priority = 1
	) {
		QueryExecute(
			"
			insert into session_preference (program, prereg_link, pm_location, start_date, priority, created_by)
			values (:program, :prereg_link, :pm_location, :start_date, :priority, 'FSY-1333')
		",
			Duplicate(arguments),
			{ datasource = variables.dsn.local }
		);
	}

	public numeric function createWard(
		required numeric stake
	) {
		// ensure unique unit_number
		local.next = QueryExecute(
			"
			select top 1 unit_number + 1 as unit_number
			from fsy_unit
			order by unit_number desc
		",
			{},
			{ datasource = variables.dsn.local }
		);

		QueryExecute(
			"
			insert into fsy_unit (unit_number, name, [type], parent, created_by)
			values (:unit_number, :name, 'Ward', :parent, 'FSY-1333')
		",
			{ unit_number = local.next.unit_number, parent = arguments.stake, name = "ward_#local.next.unit_number#_FSY-1333" },
			{ datasource = variables.dsn.local, result = "local.result" }
		);

		return local.next.unit_number
	}

	public numeric function createStake() {
		// ensure unique unit_number
		local.next = QueryExecute(
			"
			select top 1 unit_number + 1 as unit_number
			from fsy_unit
			order by unit_number desc
		",
			{},
			{ datasource = variables.dsn.local }
		);

		QueryExecute(
			// Utah American Fork Area Coordinating Council
			"
			insert into fsy_unit (unit_number, name, [type], parent, created_by)
			values (:unit_number, :name, 'Stake', 466344, 'FSY-1333')
		",
			{ unit_number = local.next.unit_number, name = "stake_#local.next.unit_number#_FSY-1333" },
			{ datasource = variables.dsn.local, result = "local.result" }
		);

		return local.next.unit_number
	}

	public void function createPMSession() {
	}

	public void function createFSURecords(
		male = 0,
		female = 0
	) {
	}

	public void function teardown() {
		QueryExecute(
			"
			delete pm_session where created_by = 'FSY-1333'
			delete session_preference where created_by = 'FSY-1333'
			delete pm_location where created_by = 'FSY-1333'
			delete event where event_object = 'CONTEXT' and event_object_id in (select context_id from context where person in (select person_id from person where first_name = 'First_1333' and last_name = 'Last_1333'))
			delete context where person in (select person_id from person where first_name = 'First_1333' and last_name = 'Last_1333')
			delete fsy_unit where created_by = 'FSY-1333'
			delete person where first_name = 'First_1333' and last_name = 'Last_1333'
			delete option_item where section in (select product_id from product where short_title like 'Section_%_1333')
			delete option_group where section in (select product_id from product where short_title like 'Section_%_1333')
			delete product where short_title like '%Housing_%_1333'
			delete product where short_title like 'Section_%_1333'
			delete product where short_title = '2024FSY_1333'
		",
			{},
			{ datasource = variables.dsn.local }
		);
	}

}
