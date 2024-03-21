#
# This file an adaptation and extension of the p2pfl library (https://pypi.org/project/p2pfl/).
# Refer to the LICENSE file for licensing information.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, version 3.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#


import logging
from typing import Type

import torch

from fedstellar.learning.aggregators.aggregator import Aggregator
from fedstellar.learning.aggregators.helper import cosine_metric
from fedstellar.learning.pytorch.lightninglearner import LightningLearner
from fedstellar.node import Blockchain


class ReputationWeights(Aggregator):
	"""
	Blockchain Prototype
	"""

	def __init__(self, blockchain: Type[Blockchain], learner: Type[LightningLearner], node_name="unknown", config=None):
		super().__init__(node_name, config)
		self.config = config
		self.role = self.config.participant["device_args"]["role"]
		logging.info("[ReputationWeights] My config is {}".format(self.config))

		# TODO: dependency injection
		self.__blockchain = blockchain
		self.__learner = learner

	def aggregate(self, models):

		if len(models) == 0:
			logging.error("[ReputationWeights] Trying to aggregate models when there are no models")
			return None

		self.reputation_calculation_blockchain(models)
		models = list(models.values())

		# Total Samples
		total_samples = sum(w for _, w in models)

		# Create a Zero Model
		accum = {layer: torch.zeros_like(param) for layer, param in models[-1][0].items()}

		# TODO: request reputation for all models to aggregate
		# TODO: normalize all reputation weights to 1
		# TODO: aggregate by normalized weights

		# Add weighted models
		logging.info(f"[FedAvg.aggregate] Aggregating models: num={len(models)}")
		for model, weight in models:
			for layer in accum:
				accum[layer] += model[layer] * weight

		# Normalize Accum
		for layer in accum:
			accum[layer] /= total_samples

		# self.print_model_size(accum)

		return accum


	# TODO: check Prototype
	def reputation_calculation_blockchain(self, aggregated_models_weights):

		current_models = {}
		for subnodes in aggregated_models_weights.keys():
			sublist = subnodes.split()
			submodel = aggregated_models_weights[subnodes][0]
			for node in sublist:
				current_models[node] = submodel

		reputation_score = {}
		local_model = self.__learner.get_parameters(self.__learner)
		untrusted_nodes = list(current_models.keys())

		for untrusted_node in untrusted_nodes:
			if untrusted_node != "self.get_name()":
				untrusted_model = current_models[untrusted_node]
				cossim = cosine_metric(local_model, untrusted_model, similarity=True)
				avg_loss = self.__learner.validate_neighbour_model(self.__learner, untrusted_model)

				reputation_score[untrusted_node] = (cossim, avg_loss)

		# TODO: push local opinion to blockchain
		return reputation_score

