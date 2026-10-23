# EV Drivetrain Digital Twin

This repository contains the **MATLAB/Simulink simulations and experimental results** developed for my final-year Mechatronics Engineering project at the University of Cape Town.

The project focuses on developing and validating a **Digital Twin of an electric vehicle drivetrain test bench**. The Digital Twin models the behaviour of an induction motor drivetrain subjected to both steady-state and dynamic mechanical loading.

A vehicle road-load model was developed to calculate the torque demand associated with vehicle acceleration, rolling resistance, aerodynamic drag and road gradient. This load was used to simulate realistic drivetrain operating conditions, including a dynamic road-load profile based on the **US06 drive cycle**.

The Digital Twin was validated against experimental results obtained from the physical drivetrain under:

- No-load conditions
- Constant steady-state loads
- 200 V, 250 V and 300 V operating conditions
- Dynamic road-load testing

The results compare measured and simulated **torque, shaft speed, RMS current, mechanical power and efficiency** to evaluate the accuracy of the Digital Twin.

## Repository Contents

```text
Simulations/
    MATLAB and Simulink models used for the Digital Twin
    and vehicle road-load simulation.

Results/
    Experimental test data, processed results and
    Digital Twin validation data.
```

## Software

- MATLAB
- Simulink
- Simscape Electrical

## Author

**Nuha Adams**  
BSc Mechatronics Engineering  
University of Cape Town
