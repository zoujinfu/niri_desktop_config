#!/bin/bash
gdbus call --session --dest dev.walkercito.CopyClip --object-path /dev/walkercito/CopyClip --method org.freedesktop.Application.Activate '{}' >/dev/null 2>&1
