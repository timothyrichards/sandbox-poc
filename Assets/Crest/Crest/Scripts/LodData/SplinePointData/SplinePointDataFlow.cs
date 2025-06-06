﻿// Crest Ocean System

// Copyright 2021 Wave Harmonic Ltd

using Crest.Spline;
using UnityEngine;

namespace Crest
{
    /// <summary>
    /// Custom spline point data for flow
    /// </summary>
    [AddComponentMenu("")]
    public class SplinePointDataFlow : SplinePointDataBase
    {
        /// <summary>
        /// The version of this asset. Can be used to migrate across versions. This value should
        /// only be changed when the editor upgrades the version.
        /// </summary>
        [SerializeField, HideInInspector]
#pragma warning disable 414
        int _version = 0;
#pragma warning restore 414

        public const float k_defaultSpeed = 2f;

        [Tooltip("Flow velocity (speed of flow in direction of spline). Can be negative to flip direction."), SerializeField]
        [DecoratedField, OnChange(nameof(NotifyOfSplineChange))]
        float _flowVelocity = k_defaultSpeed;
        public float FlowVelocity { get => _flowVelocity; set => _flowVelocity = value; }

        public override Vector2 GetData()
        {
            return new Vector2(_flowVelocity, 0f);
        }
    }
}
