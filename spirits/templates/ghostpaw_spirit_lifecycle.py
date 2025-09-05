def initiate_spirit_workflow(action: str, spirit_template: dict, user_inputs: dict):
    # action: "create" or "modify"
    # spirit_template: uploaded or selected (e.g. Eira, Cantrelle)
    # user_inputs: interactive or API-driven field values

    # Step 1: Kick to tmux orchestrator
    tmux_orchestrator.start(action)

    # Step 2: Generate SPEC from template + user inputs + global defaults
    spec = auto_expand_template(spirit_template, user_inputs, global_config)

    # Step 3: Submit SPEC to Builder
    builder_job_id = builder.submit_spec(spec)

    # Step 4: Builder pulls default template, merges, builds spirit, sets up DB
    builder.build_spirit(builder_job_id)

    # Step 5: Testing phase (automated + user validation)
    test_result = tester.run_tests(builder_job_id)

    # Step 6: If test fails, push back into workflow for correction
    while not test_result.passed:
        spec = workflow.refine_spec(builder_job_id, test_result.issues)
        builder.build_spirit(builder_job_id)
        test_result = tester.run_tests(builder_job_id)

    # Step 7: Finalization
    mcp.deploy_spirit(builder_job_id)

    return "Spirit creation/modification complete and live!"