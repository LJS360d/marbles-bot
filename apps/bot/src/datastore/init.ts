import Container from 'typedi';
import CollectionsRepository from './structure/collections/repositories/collections.repository';
import CollectionsService from './structure/collections/services/collections.service';
import MarblesRepository from './structure/marbles/repositories/marbles.repository';
import MarblesService from './structure/marbles/services/marbles.service';
import TeamsRepository from './structure/teams/repositories/teams.repository';
import TeamsService from './structure/teams/services/teams.service';
import GuildsService from './structure/guilds/services/guilds.service';

async function initDatastore() {
	Container.set(MarblesRepository, new MarblesRepository());
	Container.set(
		MarblesService,
		new MarblesService(Container.get(MarblesRepository))
	);
	Container.set(TeamsRepository, new TeamsRepository());
	Container.set(TeamsService, new TeamsService(Container.get(TeamsRepository)));
	Container.set(CollectionsRepository, new CollectionsRepository());
	Container.set(
		CollectionsService,
		new CollectionsService(Container.get(CollectionsRepository))
	);
	Container.set(GuildsService, new GuildsService());
}

export default initDatastore;
