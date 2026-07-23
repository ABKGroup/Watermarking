export PLATFORM             = rapidus2hp

export DESIGN_NAME          = hercules_idecode

ifeq ($(FLOW_VARIANT), verific)
  export SYNTH_HDL_FRONTEND = verific
endif

export SRC_HOME             = /platforms/Rapidus/designs/hercules_idecode
export VERILOG_FILES        = $(sort $(wildcard $(SRC_HOME)/hercules_idecode/verilog/*.sv)) \
	$(sort $(wildcard $(SRC_HOME)/shared/verilog/*.sv)) \
	$(sort $(wildcard $(SRC_HOME)/models/cells/generic/*.sv))

export VERILOG_INCLUDE_DIRS =  $(SRC_HOME)/hercules_idecode/verilog \
	$(SRC_HOME)/shared/verilog \
	$(SRC_HOME)/models/cells/generic

.DEFAULT_SDC_FILE = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/prects.sdc
._0P3_SDC_FILE    = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/prects_0.3.sdc
export SDC_FILE = $(strip \
    $(if $(filter 0.3,$(RAPIDUS_PDK_VERSION)), \
	$(._0P3_SDC_FILE), \
	$(.DEFAULT_SDC_FILE) \
    ))

export SYNTH_HDL_FRONTEND  ?= slang


# Use $(if) to defer conditional eval until all makefiles are read
export CORE_UTILIZATION = $(strip \
    $(if $(filter 0.15,$(RAPIDUS_PDK_VERSION)), \
        $(if $(filter ra02h138_DST_45CPP,$(PLACE_SITE)), \
	    $(if $(filter slang,$(SYNTH_HDL_FRONTEND)), \
	        42, \
	        43 \
            ), \
	    $(if $(filter slang,$(SYNTH_HDL_FRONTEND)), \
	        50, \
	        48 \
            ) \
        ), \
        $(if $(filter 0.3,$(RAPIDUS_PDK_VERSION)), \
            $(if $(filter ra02h138_DST_45CPP,$(PLACE_SITE)), \
	        $(if $(filter slang,$(SYNTH_HDL_FRONTEND)), \
	            45, \
	            45 \
                ), \
	        $(if $(filter slang,$(SYNTH_HDL_FRONTEND)), \
	            58, \
	            54 \
                ) \
            ), \
            $(if $(and $(filter t0.5,$(RAPIDUS_PDK_VERSION)),$(filter SC5T,$(PLACE_SITE))), \
	        $(if $(filter slang,$(SYNTH_HDL_FRONTEND)), \
	            44, \
	            42 \
                ), \
                $(if $(filter ra02h138_DST_45CPP SC6T,$(PLACE_SITE)), \
	            $(if $(filter slang,$(SYNTH_HDL_FRONTEND)), \
	                44, \
	                43 \
                    ), \
	            $(if $(filter slang,$(SYNTH_HDL_FRONTEND)), \
	                50, \
	                48 \
                    ) \
                ) \
            ) \
        ) \
    ))

export CORE_MARGIN          = 1

# a smoketest for this option, there are a
# few last gasp iterations
export SKIP_LAST_GASP      ?= 1

export CELL_PAD_IN_SITES_GLOBAL_PLACEMENT = 0
export CELL_PAD_IN_SITES_DETAIL_PLACEMENT = 0

export SYNTH_SLANG_ARGS = --no-implicit-memories
