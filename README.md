# PUnC 16‑Bit Microprocessor Design

16‑bit PUnC microprocessor implemented in Verilog as part of Princeton University’s ECE curriculum, including a datapath, controller, LC‑3‑style instruction subset, and a test program that finds the maximum value in an array. [file:115][file:114]

## Overview

PUnC is a 16‑bit stored‑program computer that uses a subset of the LC‑3 instruction set. It is unpipelined and follows a fetch–decode–execute cycle with separate datapath and control modules. [file:115]

The design includes memory, a register file with eight 16‑bit general‑purpose registers, condition‑code flags (N, Z, P), a program counter, an instruction register, and an ALU, connected through a custom datapath and driven by a finite state machine controller. [file:115]

## Repository layout

- `src/` – Verilog modules for the datapath, controller/FSM, top‑level PUnC integration, and supporting logic. [file:115]  
- `tests/` – Verilog testbench that exercises individual instructions and full programs using provided macros and memory images. [file:115]  
- `images/` – LC‑3‑style memory image (`.vmh`) files, including TA‑provided instruction tests and a custom program that computes the maximum of an integer array. [file:115][file:114]  
- `docs/` – Project write‑up, datapath diagram, and control‑signal table from the final report. [file:114][file:115]

## Demonstration program: array maximum

The repository includes an LC‑3 assembly program that traverses an array of five integers stored in memory, compares elements via a subroutine, and stores the largest value back to memory using instructions such as LEA, LD, AND, LDR, JSR, ADD, BR, ST, HALT, NOT, and RET. [file:114]
